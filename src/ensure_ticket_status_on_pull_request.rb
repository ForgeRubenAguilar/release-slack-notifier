require 'json'
require "parallel"

# On PR Open or Update excluding development or master
# Grab JIRA out of branch name
# Check if pivotal
# Grab JIRA issue from api
# Fail on missing JIRA
# Fail on JIRA not being in accepted/closed/delivered
# Pass if label exists on JIRA no-impact-on-release

pivotal_team_project_map = {
  "BAT": "2530518"
}

alternative_ticket_system_map = {
  "BAT": "pivotal"
}



def pivotal_story_endpoint(project_id, story_id) {
  "https://www.pivotaltracker.com/n/projects/#{project_id}/stories/#{story_id}"
}

def verify_pivotal_story(story_json) {
  # Missing stories are not permissible, ensure accepted state.
  story_state = story_json.dig("current_state")
  story_missing = story_state.nil?
  story_accepted = story_state.downcase == "accepted"

  (!story_missing) && story_accepted
}

def jira_ticket_endpoint(ticket_id) {
  "https://forgeglobal.atlassian.net/rest/api/2/issue/#{ticket_id}"
}

VALID_JIRA_STATUSES = ["accepted", "closed", "delivered"].freeze
NO_IMPACT_JIRA_LABEL = "no-impact-on-release"
def verify_jira_ticket(ticket_json) {
  # Missing tickets are not permissible, ensure accepted status.
  ticket_status = resp.dig("fields", "status", "name")
  ticket_missing = ticket_status.nil?
  ticket_accepted = VALID_JIRA_STATUSES.include?(ticket_status.downcase)

  # Features behind feature flags or manually scheduled jobs have a workaround with the label.
  ticket_labels = resp.dig("fields", "labels")
  ticket_no_impact_label = ticket_labels&.include?(NO_IMPACT_JIRA_LABEL)

  (!ticket_missing) && (ticket_accepted || ticket_no_impact_label)
}

def determine_ticket_type(ticket_id) {
  last_dash = ticket_id.rindex("-")
  if !last_dash.nil?
    team_prefix = ticket_id[0..last_dash].upcase
    alternative_ticket_system_map[team_prefix] if alternative_ticket_system_map.key?(team_prefix)
  end
  "jira"
}

def dispatch_ticket_request(ticket_type, ticket_id) {
  case ticket_type
  when "pivotal"

    status = verify_pivotal_story()
  when "jira"
    status = verify_jira_ticket()
  else
    {
      "status": "fail",
      "message": "Unrecognized ticket system for ticket #{ticket_id}"
    }
  end
}

ticket_id = "" # strip off pr branch
ticket_type = determine_ticket_type(ticket_id)
return_response = dispatch_ticket_request(ticket_type, ticket_id)


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

  [ticket_id, status, title] # title nil for nonexist ticket
end

lines.each do |ticket_id, status, title|
  puts "#{ticket_id} - #{status} - #{title}"
end