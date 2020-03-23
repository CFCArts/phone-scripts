#!/usr/bin/env ruby -w

require 'CSV'

counts       = Hash.new(0)
phone_number = ""

FEB_START      = DateTime.parse("2020-02-01 00:00:00 EST").to_time
MAR_START      = DateTime.parse("2020-03-01 00:00:00 EST").to_time
ONE_WEEK_AGO   = Time.now - (7 * 24 * 60 * 60)
SIXTY_DAYS_AGO = Time.now - (60 * 24 * 60 * 60)

CSV.read(ARGV[0], headers: true).each do |r|
  phone_number = r["Phone Number"] if phone_number.empty?

  counts[:total] += 1

  # Incoming calls that are redirected elsewhere are logged at least twice: as an
  # incoming call, and an outgoing call to the next number. And then another if it
  # went to voicemail after that. Count these outgoing redirects for fun, then skip
  # them so we don't count them as real outgoing calls
  if r["Call Direction"] == "Originating"
    case r["Special Call Type"]
    when "Call Forward No Answer", "Call Forward Busy"
      counts[:sent_to_voicemail] += 1
      next
    when "Call Forward Always"
      counts[:forwarded] += 1
      next
    when "Call Forward Selective"
      if r["Called Number"] = "500"
        counts[:sent_to_aa] += 1
        next
      else
        warn "Warning: unhandled 'Call Forward Selective' call"
        warn r.inspect
        puts
      end
    when "BroadWorks Anywhere Location"
      counts [:attempted_to_send_to_cell] += 1
      next
    when nil
      if r["Caller Name"] == "Voice Portal Voice Portal"
        if r["Calling Number"] == phone_number
          counts[:calls_to_voice_portal] += 1
          next
        elsif r["Calling Number"] != phone_number
          counts[:sent_to_voicemail] += 1
          next
        end
      elsif r["Call Category"] == "private"
        # Regular outbound call to inter-office number
      elsif r["Caller Name"] == nil
        # Regular outbound call to external number
      else
        warn "Warning: unhandled empty call type"
        warn r.inspect
        puts
      end
    else
       warn "Warning: unknown call type '#{r['Special Call Type']}':"
       warn r.inspect
       puts
    end
  end


  # Time zone looks local? but not in the CSV... so we'll just pick EST to get close
  time = DateTime.parse(r["Call Date"] + " " + r["Call Time"] + "EST").to_time

  if r["Call Direction"] != "Terminating" && r["Call Direction"] != "Originating"
    raise "Unknown Call Direction: #{r["Call Direction"]}"
  end

  if time > ONE_WEEK_AGO
    if r["Call Direction"] == "Terminating"
      counts[:incoming_7] += 1
    elsif r["Call Direction"] == "Originating"
      counts[:outgoing_7] += 1
    end
  end

  if time >= SIXTY_DAYS_AGO
    if r["Call Direction"] == "Terminating"
      counts[:incoming_60] += 1
    elsif r["Call Direction"] == "Originating"
      counts[:outgoing_60] += 1
    end
  elsif time < (SIXTY_DAYS_AGO - (1 * 24 * 60 * 60))
    # They only provide two months of logs. Add a grace day because it's
    # probably a batch process
    warn "Warning: unexpected call log from more than two months ago"
    warn r.inspect
  end

  if time >= FEB_START && time < MAR_START
    if r["Call Direction"] == "Terminating"
      counts[:incoming_feb] += 1
    elsif r["Call Direction"] == "Originating"
      counts[:outgoing_feb] += 1
    end
  end
end

bold  = "\033[31;1;4m"
reset = "\033[0m"

puts <<-OUTPUT

Internal number #{phone_number} (#{counts[:total]} total logs)

           Sent to voicemail: #{counts[:sent_to_voicemail]}
                  Sent to AA: #{counts[:sent_to_aa]}
                   Forwarded: #{counts[:forwarded]}
   Attempted to ring to cell: #{counts[:attempted_to_send_to_cell]}
Calls to portal from handset: #{counts[:calls_to_voice_portal]}
    

#{bold}Incoming calls#{reset}
     Past week: #{counts[:incoming_7]}
      February: #{counts[:incoming_feb]}
  Last 60 days: #{counts[:incoming_60]}

#{bold}Outgoing calls#{reset}
     Past week: #{counts[:outgoing_7]}
      February: #{counts[:outgoing_feb]}
  Last 60 days: #{counts[:outgoing_60]}

OUTPUT
