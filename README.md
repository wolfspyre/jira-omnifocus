jira-omnifocus
==============

Ruby script to create and manage OmniFocus tasks based on your Jira tickets

This script started as:
http://www.digitalsanctuary.com/tech-blog/general/jira-to-omnifocus-integration.html

I've modified it a bit.

###What it does:

First it runs through all the unresolved Jira tickets that are assigned to you.
If it finds a ticket in jira that it hasn't already created an OmniFocus task for, it creates a new one.

The title of the task is the Jira ticket number followed by the summary from the ticket.  The note part of the OmniFocus task is the URL to the Jira ticket, and the current status.  I chose not to pull over the full description, or comment history into the task notes as it is usually more than I want to see in OmniFocus.

It subsequently checks all tasks in OmniFocus that look like they are related to Jira tickets, and checks to see if the matching ticket has been resolved.  If so, it marks the task as complete.


Very simple.  The Ruby code is pretty simple, and it should be easy to modify to do other things to meet your specific needs.

###Usage:

  * You will need to install a few gems.
    * This can be tackled by running `bundle install`
    * Or by looking at the `Gemfile` and adding the required gems ala: `gem install rb-appscript json`

  * You will need to copy conf.d/script_config.yaml to conf.d/script_override.yaml.

  Place your specific configuration needs there. **Please note this version does not hide/encrypt your password**.
  * Update `bin/ENV_Settings.sh.example` with your relevant environment variables.

  * I setup mine to run via cron. This is my crontab entry:
    */5 * * * * /bin/bash ~/git/jira-omnifocus/bin/ENV_settings.sh >/dev/null 2>&1


That should be it!  If it doesn't work, try using pry to debug while running it manually.

I will try to offer support, but I don't know Ruby too terribly well, and it's hard to poke into the applescript bridge.

###TODO:
  * add means to create the project if it doesn't exist
  * add means to get all tickets assigned to me which don't have labels (ie 'the rest of my tickets')
  * add means to get other project labels



