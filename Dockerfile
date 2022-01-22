FROM ruby:2.7

COPY src /usr
WORKDIR /usr/src
RUN bundle install


ENTRYPOINT ["ruby", "/src/jira_message.rb"]