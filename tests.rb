# testing for project rubin

require_relative 'classes.rb'


db = DatabaseBox.new('sqlite://test.db')
db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)
db.read_messages_from_database
puts db.hash_key('here we go')