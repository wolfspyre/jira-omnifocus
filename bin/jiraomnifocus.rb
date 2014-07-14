#!/Users/wnoble/.rvm/rubies/ruby-1.9.3-p547/bin/ruby
require 'appscript'
require 'rubygems'
require 'net/http'
require 'json'
require 'uri'
require 'pry'
require 'pry-remote'
require 'yaml'

# Put config variables in a file outside the script
#
#
script_config = YAML.load_file("conf.d/script_config.yaml")
if File.exists?("conf.d/script_override.yaml")
  script_config = script_config.merge(YAML.load_file("conf.d/script_override.yaml"))
end
if script_config['jira_baseurl'] == 'https://jira.mysite.com'
  #script.override hasn't been populated. we should fail here.
  raise StandardError "Custom Settings have not been entered. Please populate conf.d/script_override.yaml with your data. Reference conf.d/script_config.yaml for an example"
end
#JIRA Configuration
JIRA_BASE_URL = script_config['jira_baseurl']
USERNAME      = script_config['jira_username']
PASSWORD      = script_config['jira_password']

#OmniFocus Configuration
DEFAULT_CONTEXT = script_config['omnifocus_default_context']
DEFAULT_PROJECT = script_config['omnifocus_default_project']
FLAGGED         = script_config['omnifocus_flagged']
PROJECTS        = script_config['omnifocus_projects']

#Script config
#
DEBUG = script_config['script_debug']#int. 0-5



def debug_msg(message='',level=9)
  if level.to_i < DEBUG.to_i
    #we should print the debug message
    p "Debug[#{level}]: #{message}"
  end
end


# This method gets all issues that are assigned to your USERNAME and whos status isn't Closed or Resolved.  It returns a Hash where the key is the Jira Ticket Key and the value is the Jira Ticket Summary.
def get_issues(label='',mode)
  debug_msg("get_issues: #{label}",3)
  case mode
  when 'inclusive'
    uri = URI.parse(JIRA_BASE_URL + "/rest/api/2/search?jql=assignee+%3D+currentUser()+AND+status+not+in+(Closed,+Resolved)+AND+labels+in(#{label})")
    debug_msg(uri,9)
  when 'exclusive'
    uri = URI.parse(JIRA_BASE_URL + "/rest/api/2/search?jql=assignee+%3D+currentUser()+AND+status+not+in+(Closed,+Resolved)+AND+labels+not+in(#{label})")
    debug_msg(uri,9)
  else
    raise StandardError "mode has an unsupported value: #{mode}. should be 'inclusive' or 'exclusive'"
  end
  jira_issues = Hash.new
  j_issue = Hash.new
  # This is the REST URL that will be hit.  Change the jql query if you want to adjust the query used here
 # uri = URI.parse(JIRA_BASE_URL + "/rest/api/2/search?jql=assignee+%3D+currentUser()+AND+status+not+in+(Closed,+Resolved)+AND+labels+in(#{label})")

  Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    request = Net::HTTP::Get.new(uri.request_uri)
    debug_msg(request,10)
    request.basic_auth("#{USERNAME}", "#{PASSWORD}")
    response = http.request (request)
     debug_msg(response,10)
    # If the response was good, then grab the data
    if response.code =~ /20[0-9]{1}/
        data = JSON.parse(response.body)
        debug_msg("DATA: #{data}",9)
        data["issues"].each do |item|
          debug_msg("ITEM: #{item}",10)
          jira_id = item["key"]
          j_id = item['key']
          j_issue[j_id] = Hash.new
          j_issue[j_id]['status']  = item['fields']['status']['name']
          j_issue[j_id]['summary'] = item['fields']['summary']
#          p item
#          p "-----------------------------------------"
#          binding.pry;
           summary_status = '[' + item['fields']['status']['name']+ '] '+item['fields']['summary']
#          jira_issues[jira_id] = item['fields']['summary']
#          jira_issues[jira_id] = item['fields']['status']['name']
#           jira_issues[jira_id].['summary'] = item['fields']['summary']
#           jira_issues[jira_id].['status']  = item['fields']['status']['name']
           jira_issues[jira_id]  = item['fields']['summary']

      #    binding.pry;
        end
    else
     raise StandardError, "Unsuccessful response code " + response.code + " for #{label} "
    end
  end
  #return jira_issues
  return j_issue
end



# This method adds a new Task to OmniFocus based on the new_task_properties passed in
def add_task(omnifocus_document, new_task_properties, task_ext_ticket_key)
  debug_msg("add_task: #{omnifocus_document} #{new_task_properties} #{task_ext_ticket_key}", 3)
  # If there is a passed in OF project name, get the actual project object
  if new_task_properties['project']
    proj_name = new_task_properties["project"]
    proj = omnifocus_document.flattened_tasks[proj_name]
    debug_msg("PROJ: #{proj}", 10)
  end


  #TODO
  #If the project/label doesn't exist, create it.
  #



  # TODO: change this to match off the jira id as a regex, not ==, this permits the subject to change
  #
  # Check to see if there's already an OF Task with that name in the referenced Project
  # If there is, just stop.
  name   = new_task_properties["name"]
  # binding.pry;
  exists = proj.tasks.get.find { |entry|  debug_msg("exists entry: #{entry}",10); entry.name.get  == name}
  #I tried several means of trying to get this to be a match, alas, I couldn't get it to work easily.
  # problem for future me.
  # /task_ext_ticket_key/ }#entry.name.get =~ /task_ext_ticket_key/ }
  #tasks.get.find.match(task_ext_ticket_key)# { |t|} # t.name == /task_ext_ticket_key/ }
  if exists
    debug_msg('exists is true',6)
    return false
  end
  #  return false if exists

  # If there is a passed in OF context name, get the actual context object
  if new_task_properties['context']
    ctx_name = new_task_properties["context"]
    ctx = omnifocus_document.flattened_contexts[ctx_name]
    debug_msg("CTX: #{ctx}", 9)
  end

  # Do some task property filtering.  I don't know what this is for, but found it in several other scripts that didn't work...
  tprops = new_task_properties.inject({}) do |h, (k, v)|
    h[:"#{k}"] = v
    h
  end

  # Remove the project property from the new Task properties, as it won't be used like that.
  tprops.delete(:project)
  # Update the context property to be the actual context object not the context name
  tprops[:context] = ctx if new_task_properties['context']

  # You can uncomment this line and comment the one below if you want the tasks to end up in your Inbox instead of a specific Project
#  new_task = omnifocus_document.make(:new => :inbox_task, :with_properties => tprops)

  # Make a new Task in the Project
  proj.make(:new => :task, :with_properties => tprops)

  puts "task created"
  return true
end

# This method is responsible for getting your assigned Jira Tickets and adding them to OmniFocus as Tasks
def add_jira_tickets_to_omnifocus ()
  debug_msg('add_jira_tickets_to_omnifocus',3)
  #iterate through the projects array, add tickets to the proper project based on the results from the label query.
  #
  #This adds a relationship between your OmniFocus 'projects' and the labels you use in jira. be warned.

  PROJECTS.each do |project_label|
    debug_msg("add_jira_tickets_to_omnifocus: Label: #{project_label}",2)
    # Get the open Jira issues assigned to you
    results = get_issues(project_label,'inclusive')
    if results.nil?
      debug_msg("add_jira_tickets_to_omnifocus: No results from Jira matching #{project_label}",0)
      exit
    end

  # Get the OmniFocus app and main document via AppleScript
   # binding.pry;
    omnifocus_document = Appscript.app.by_name('/Applications/OmniFocus.app').default_document
    # Iterate through resulting issues.
    results.each do |jira_id, hash|
      debug_msg("add_jira_tickets_to_omnifocus: Jira_ID: #{jira_id} Hash: #{hash}", 8)
      #binding.pry;
      jira_summary = hash['summary']
      jira_status  = hash['status']
      # Create the task name by adding the ticket hash to the jira ticket key
      task_name = "#{jira_id}: #{jira_summary}"
      # Create the task notes with the Jira Ticket URL
      #status = foo
      task_notes  = "ID: #{jira_id}\r\nURL: #{JIRA_BASE_URL}/browse/#{jira_id} \r\nStatus: #{jira_status} "

      # Build properties for the Task
      @props = {}
      @props['name'] = task_name
      @props['project'] = project_label
      @props['context'] = DEFAULT_CONTEXT
      @props['note'] = task_notes
      @props['flagged'] = FLAGGED
      add_task(omnifocus_document, @props, jira_id)
    end
  end#end iteration
  #get the list of tickets which are assigned to the user, but not caught by the existing label search
  projectstring =  PROJECTS * ","
  exclusive_results = get_issues(projectstring,'exclusive')
  debug_msg("add_jira_tickets_to_omnifocus: Fetching tickets not tagged with the labels: #{projectstring}",1)
  if exclusive_results.nil?
    debug_msg("add_jira_tickets_to_omnifocus: No results from Jira which aren't already covered by the previous searches",0)
    exit
  end
  # TODO: I feel like an idiot duplicating this code. we should change it
  # Get the OmniFocus app and main document via AppleScript
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document
  debug_msg("add_jira_tickets_to_omnifocus: omnifocus_document: #{omnifocus_document}", 10)
  # Iterate through resulting issues.
  exclusive_results.each do |jira_id, hash|
    debug_msg("add_jira_tickets_to_omnifocus: exclusive iterator: jira_id: #{jira_id} hash: #{hash}",11)
    #binding.pry;
    jira_summary = hash['summary']
    jira_status  = hash['status']
    # Create the task name by adding the ticket hash to the jira ticket key
    task_name = "#{jira_id}: #{jira_summary}"
    # Create the task notes with the Jira Ticket URL
    #status = foo
    task_notes  = "ID: #{jira_id}\r\nURL: #{JIRA_BASE_URL}/browse/#{jira_id} \r\nStatus: #{jira_status} "
   # Build properties for the Task
    @props            = {}
    @props['context'] = DEFAULT_CONTEXT
    @props['flagged'] = FLAGGED
    @props['name']    = task_name
    @props['note']    = task_notes
    @props['project'] = DEFAULT_PROJECT
    add_task(omnifocus_document, @props, jira_id )
  end
end

def mark_resolved_jira_tickets_as_complete_in_omnifocus ()
  debug_msg("mark_resolved_jira_tickets_as_complete_in_omnifocus:",3)
  # get tasks from the project
  omnifocus_app = Appscript.app.by_name("OmniFocus")
  omnifocus_document = omnifocus_app.default_document
  ctx = omnifocus_document.flattened_tasks
 #binding.pry;
  ctx.get.each do |task|
    debug_msg("mark_resolved_jira_tickets_as_complete_in_omnifocus: #{task}",4)
   # p task
    if ( !task.note.get.match(JIRA_BASE_URL) or !task.note.get.match(/ID: ([[:upper:]]*-[[:digit:]]*)/) )
     # p 'task.note.get.match failed for '#ß task
     # p task.note.get
    else
      #I think we should add logic here to see the task is completed already.
      full_url=task.note.get
      jira_id_foo=full_url.scan(/ID: ([[:upper:]]*-[[:digit:]]*)/)
      if jira_id_foo.is_a?(Array)
       # p "Array!"
        jira_id = jira_id_foo[0][0]
       # binding.pry;
      else
        jira_id = jira_id_foo
      end
      #ßfull_url.scan(/URL: ([[:upper:]]*-[[:digit:]]*)/)
      #binding.pry;
#      jira_id=full_url.sub(JIRA_BASE_URL+"/browse/","").
      #   binding.pry;
      tstate=task.completed.get
      if tstate == false
        # try to parse out jira id
        # check status of the jira
        debug_msg("curling for #{jira_id} - Completed: #{tstate}",6)
        uri = URI.parse(JIRA_BASE_URL + '/rest/api/2/issue/' + jira_id)
        # p uri
        Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth("#{USERNAME}", "#{PASSWORD}")
          response = http.request(request)

          if response.code =~ /20[0-9]{1}/
            data = JSON.parse(response.body)
            resolution = data["fields"]["resolution"]
            if resolution != nil
              # if resolved, mark it as complete in OmniFocus
              task.completed.set(true)
            end
          else
           raise StandardError, "Unsuccessful response code " + response.code + " for issue " + issue
          end
        end
      else
        debug_msg("not updating status for closed ticket #{jira_id}",1)
      end#end task is not completed
    end
  end
end

def app_is_running(app_name)
  debug_msg("app_is_running: #{app_name}",3)
  `ps aux` =~ /#{app_name}/ ? true : false
end

def main ()
   if app_is_running("OmniFocus")
    add_jira_tickets_to_omnifocus
    mark_resolved_jira_tickets_as_complete_in_omnifocus
   end
end

main
