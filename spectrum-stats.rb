#!/usr/bin/env ruby -w

require 'CSV'

counts = Hash.new { |h, phone_number|
           h[phone_number] = Hash.new(0)
         }
call_counts_by_day = Hash.new(0)
earliest_time_seen = nil
last_time_seen     = nil

FEB_START      = DateTime.parse("2020-02-01 00:00:00 EST").to_time
MAR_START      = DateTime.parse("2020-03-01 00:00:00 EST").to_time
ONE_WEEK_AGO   = Time.now - (7 * 24 * 60 * 60)
SIXTY_DAYS_AGO = Time.now - (60 * 24 * 60 * 60)

CSV.read(ARGV[0], headers: true).each do |r|
  # Time zone looks local? but not in the CSV... so we'll just pick EDT to get close
  time = DateTime.parse(r["Call Date"] + " " + r["Call Time"] + "EDT").to_time

  earliest_time_seen = time if earliest_time_seen.nil? || earliest_time_seen > time
  last_time_seen = time if last_time_seen.nil? || last_time_seen < time

  pn = r["Phone Number"]

  counts[pn][:total] += 1

  # Incoming calls that are redirected elsewhere are logged at least twice: as an
  # incoming call, and an outgoing call to the next number. And then another if it
  # went to voicemail after that. Count these outgoing redirects for fun, then skip
  # them so we don't count them as real outgoing calls
  if r["Call Direction"] == "Originating"
    case r["Special Call Type"]
    when "Call Forward No Answer", "Call Forward Busy"
      counts[pn][:sent_to_voicemail] += 1
      next
    when "Call Forward Always"
      counts[pn][:forwarded] += 1
      next
    when "Call Forward Selective"
      if r["Called Number"] = "500"
        counts[pn][:sent_to_aa] += 1
        next
      else
        warn "Warning: unhandled 'Call Forward Selective' call"
        warn r.inspect
        puts
      end
    when "BroadWorks Anywhere Location"
      counts[pn][:attempted_to_send_to_cell] += 1
      next
    when nil
      if r["Caller Name"] == "Voice Portal Voice Portal"
        if r["Calling Number"] == pn
          counts[pn][:calls_to_voice_portal] += 1
          next
        elsif r["Calling Number"] != pn
          counts[pn][:sent_to_voicemail] += 1
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

  call_counts_by_day[time.to_date] += 1

  if r["Call Direction"] != "Terminating" && r["Call Direction"] != "Originating"
    raise "Unknown Call Direction: #{r["Call Direction"]}"
  end

  if time > ONE_WEEK_AGO
    if r["Call Direction"] == "Terminating"
      counts[pn][:incoming_7] += 1
    elsif r["Call Direction"] == "Originating"
      counts[pn][:outgoing_7] += 1
    end
  end

  if time >= SIXTY_DAYS_AGO
    if r["Call Direction"] == "Terminating"
      counts[pn][:incoming_60] += 1
    elsif r["Call Direction"] == "Originating"
      counts[pn][:outgoing_60] += 1
    end
  elsif time < (SIXTY_DAYS_AGO - (1 * 24 * 60 * 60))
    # They only provide two months of logs. Add a grace day because it's
    # probably a batch process
    warn "Warning: unexpected call log from more than two months ago"
    warn r.inspect
  end

  if time >= FEB_START && time < MAR_START
    if r["Call Direction"] == "Terminating"
      counts[pn][:incoming_feb] += 1
    elsif r["Call Direction"] == "Originating"
      counts[pn][:outgoing_feb] += 1
    end
  end
end

(earliest_time_seen.to_date..last_time_seen.to_date).each do |date|
  if !call_counts_by_day.has_key?(date)
    call_counts_by_day[date] = 0
  end
end

blue  = "\033[34;7m"
bu = "\033[1;4m"
reset = "\033[0m"

counts.each do |pn, stats|
  other_stats = ""
  {"sent to voicemail":            stats[:sent_to_voicemail],
   "sent to AA":                   stats[:sent_to_aa],
   "forwarded":                    stats[:forwarded],
   "attempted to ring to cell":    stats[:attempted_to_send_to_cell],
   "to portal from handset": stats[:calls_to_voice_portal]}.each do |txt, number|
     other_stats += "  #{number} call#{'s' if number > 1} #{txt}\n" if number > 0
  end

  puts <<-OUTPUT

Internal number #{blue}#{pn}#{reset} (#{stats[:total]} total logs)
#{"\n" unless other_stats.empty?}#{other_stats}
  #{bu}Incoming calls #{reset}       #{bu}Outgoing calls #{reset}
     Past week: #{stats[:incoming_7]}          Past week: #{stats[:outgoing_7]}
      February: #{stats[:incoming_feb]}           February: #{stats[:outgoing_feb]}
  Last 60 days: #{stats[:incoming_60]}       Last 60 days: #{stats[:outgoing_60]}


OUTPUT

end

puts "Earliest call seen: #{earliest_time_seen}"
puts "    Last call seen: #{last_time_seen}"
puts
puts "By day:"
call_counts_by_day.sort_by { |k, v| k.to_s }.each_with_index do |(date, count), i|
  puts "  #{(i + 1).to_s.rjust(2)}. #{date}: #{count}"
end
