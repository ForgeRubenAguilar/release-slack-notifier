require 'json'
require "parallel"

# Release Friend

# Orphaned tickets if we don't have tickets in branch name
# Create PR to master in morning, have at least 1 product owner from each ticket approve pr, manually rerun once before merge via actions menu.
# excuse-<teame> pr tag to skip that team

# remove to env var
ticket_prefixes = ["DATA","SHAR"]
team_release_owners_slack_mentions = {
  "DATA": ["@keithfarley"],
  "SHAR": ["@mattmayne"]
}

commits = `git log --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative master..development`
ticket_ids = commits.split("\n").map {|line| line.scan(/DATA\-\d+/) + line.scan(/SHAR\-\d+/) }.flatten.uniq

lines = []
Parallel.map(ticket_ids, in_processes: 4) do
  # remove creds to env var
  username = "peter.min@forgeglobal.com"
  token = ""
  resp = `curl -s -u #{username}:#{token} -X GET -H "Content-Type: application/json" https://forgeglobal.atlassian.net/rest/api/2/issue/#{ticket_id}`
  resp = JSON.parse(resp)
  status = resp.dig("fields", "status", "name")
  # label no-impact-on-release for bypass
  # add PR link, require product approval on PR
  title = resp.dig("fields", "summary")

  [ticket_id, status, title] # title/status nil for nonexist ticket
end

lines.each do |ticket_id, status, title|
  puts "#{ticket_id} - #{status} - #{title}"
end