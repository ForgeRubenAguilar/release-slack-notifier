require 'json'

ENV["INPUT_TEAM_TO_PROJECT_ID"] = '{ "BAT": "2530518" }'

ENV["INPUT_TEAM_TO_PROJECT_SYSTEM"] = '{ "BAT": "pivotal" }'

ENV["INPUT_PROJECT_SYSTEM_CREDENTIALS"] = '{ "jira": ["", ""], "pivotal": ["", ""] }'

class ApiCredentials
  def self.ticket_system_creds 
    JSON.parse(ENV["INPUT_PROJECT_SYSTEM_CREDENTIALS"])
  end
end

class TicketSystemQuery
  JIRA = "jira"
  PIVOTAL = "pivotal"

  def find_ticket_system(ticket)
    ticket_system = TicketSystemQuery::JIRA
    if alternative_team_ticket_system_map.key?(ticket.team_segment)
      team_ticket_system = alternative_team_ticket_system_map[ticket.team_segment] 
      if !team_ticket_system.nil? && team_ticket_system != ""
        ticket_system = team_ticket_system
      end
    end

    ticket_system
  end

  def find_project_id(ticket)
    project_id = nil
    if team_project_id_map.key?(ticket.team_segment)
      team_project_id = team_project_id_map[ticket.team_segment] 
      if !team_project_id.nil? && team_project_id != ""
        project_id = team_project_id
      end
    end

    project_id
  end

  private

  def alternative_team_ticket_system_map 
    @alternative_team_ticket_system_map ||= JSON.parse(ENV["INPUT_TEAM_TO_PROJECT_SYSTEM"])
  end

  def team_project_id_map
    @team_project_id_map ||= JSON.parse(ENV["INPUT_TEAM_TO_PROJECT_ID"])
  end
end

class Ticket 
  attr_accessor :raw_ticket_id, :team_segment, :id_segment, :ticket_system, :project_id

  def initialize(ticket_system_query, ticket_id)
    @raw_ticket_id = ticket_id
    @team_segment, @id_segment = extract_ticket_team_and_numeric_segments(ticket_id)
    @ticket_system = ticket_system_query.find_ticket_system(self)
    @project_id = ticket_system_query.find_project_id(self)
  end

  private 

  def extract_ticket_team_and_numeric_segments(ticket_id) 
    last_dash = ticket_id.rindex("-")
    if last_dash.nil?
      raise StandardError.new("Ticket format failed to parse '#{ticket_id}'. Could not locate a '-' to split.")
    end
    team_segment = ticket_id[0..last_dash-1].upcase
    numeric_segment = ticket_id[last_dash+1..ticket_id.length].upcase

    [team_segment, numeric_segment]
  end
end


def pivotal_story_endpoint(project_id, story_id) 
  "https://www.pivotaltracker.com/services/v5/projects/#{project_id}/stories/#{story_id}"
end

VALID_PIVOTAL_STATUSES = ["accepted"].freeze
def verify_pivotal_story(story_json, ticket) 
  # Missing stories are not permissible, ensure accepted state.
  story_state = story_json.dig("current_state")
  story_missing = story_state.nil?
  story_accepted = VALID_PIVOTAL_STATUSES.include?(story_state&.downcase)

  raise StandardError.new("Story #{ticket.raw_ticket_id} could not be found in #{TicketSystemQuery::PIVOTAL}.") if story_missing
  raise StandardError.new("Story #{ticket.raw_ticket_id} is in state '#{story_state&.downcase}', which is not in acceptable state(s) (#{VALID_JIRA_STATUSES}).") if !story_accepted
end

def jira_ticket_endpoint(ticket_id) 
  "https://forgeglobal.atlassian.net/rest/api/2/issue/#{ticket_id}"
end

VALID_JIRA_STATUSES = ["accepted", "closed", "delivered"].freeze
def verify_jira_ticket(ticket_json, ticket) 
  # Missing tickets are not permissible, ensure accepted status.
  ticket_status = ticket_json.dig("fields", "status", "name")
  ticket_missing = ticket_status.nil?
  ticket_accepted = VALID_JIRA_STATUSES.include?(ticket_status&.downcase)

  raise StandardError.new("Ticket #{ticket.raw_ticket_id} could not be found in #{TicketSystemQuery::JIRA}.") if ticket_missing
  raise StandardError.new("Ticket #{ticket.raw_ticket_id} is in status '#{ticket_status&.downcase}', which is not in acceptable status(es) (#{VALID_JIRA_STATUSES}).") if !ticket_accepted
end

def dispatch_ticket_request(ticket) 
  case ticket.ticket_system
  when TicketSystemQuery::PIVOTAL
    username, token = ApiCredentials::ticket_system_creds[ticket.ticket_system]
    url = pivotal_story_endpoint(ticket.project_id, ticket.id_segment)
    resp = `curl -s -X GET -H "X-TrackerToken: #{token}" -H "Content-Type: application/json" #{url}`
    json_resp = JSON.parse(resp)
    verify_pivotal_story(json_resp, ticket)
  when TicketSystemQuery::JIRA
    username, token = ApiCredentials::ticket_system_creds[ticket.ticket_system]
    url = jira_ticket_endpoint(ticket.raw_ticket_id)
    resp = `curl -s -u #{username}:#{token} -X GET -H "Content-Type: application/json" #{url}`
    json_resp = JSON.parse(resp)
    verify_jira_ticket(json_resp, ticket)
  else
    raise StandardError.new("Unrecognized ticket system for ticket #{ticket.raw_ticket_id}")
  end
end

teams = ENV["INPUT_TEAMS"]
branch_name = ""
# parse ticket id out of branch

ticket_id = "SHAR-1365" # strip off pr branch

ticket_system = TicketSystemQuery.new
ticket = Ticket.new(ticket_system, ticket_id)
return_response = dispatch_ticket_request(ticket)
puts "Ticket #{ticket.raw_ticket_id} passed all ticket checks."

# ------

# # remove to env var
# ticket_prefixes = ["DATA","SHAR"]
# team_release_owners_slack_mentions = {
#   "DATA": ["@keithfarley"],
#   "SHAR": ["@mattmayne"]
# }

# commits = `git log --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative master..development`
# ticket_ids = commits.split("\n").map {|line| line.scan(/DATA\-\d+/) + line.scan(/SHAR\-\d+/) }.flatten.uniq

# lines = []
# Parallel.map(ticket_ids, in_processes: 4) do
#   # remove creds to env var
#   username = "peter.min@forgeglobal.com"
#   token = ""
#   resp = `curl -s -u #{username}:#{token} -X GET -H "Content-Type: application/json" https://forgeglobal.atlassian.net/rest/api/2/issue/#{ticket_id}`
#   resp = JSON.parse(resp)
#   status = resp.dig("fields", "status", "name")
#   # label no-impact-on-release for bypass
#   # add PR link, require product approval on PR
#   title = resp.dig("fields", "summary")

#   [ticket_id, status, title] # title nil for nonexist ticket
# end

# lines.each do |ticket_id, status, title|
#   puts "#{ticket_id} - #{status} - #{title}"
# end