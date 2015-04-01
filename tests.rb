# testing for project rubin

require_relative 'classes.rb'

db = DatabaseBox.new
db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)
db.read_messages_from_database

# db.read_messages_from_database
#db.write_

# db.register_key('blah', 'host', 'private key', 'public key')
# irc = RelayChat.new('asdfj', 'aksdjflö', 'irc.freenode.org', '#asdfjhasdkjfh')

a, b = db.output_host_keypair
puts a.to_s
puts b.to_s