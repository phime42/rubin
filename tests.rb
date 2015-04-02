# testing for project rubin
require_relative 'classes.rb'
db = DatabaseBox.new
# db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)

adapter = EncryptedAdapter.new
adapter.write_encrypted_message(Time.now, 'email', false, 'Johnathan', 'long_text', 'NULL')

cb = CryptoBox.new
cb.testing_generate_receiving_keypair

# puts db.output_all_keys
# puts db.output_host_keypair  # => public private

# irc = RelayChat.new('happybot', 'none', 'irc.freenode.org', '#asdfjhasdkjfh')
# adapter.read_encrypted_message_by_id(1, 2)
db.register_new_client('Heimathafen', 'http://irc.freenode.org', 'irc', 'happybot', 'just a happy bot', '#happybotsparadise')
# Starter.new
db.revoke_key(Base64.decode64('Ddh1VHOvczIpeDGGMocwYyBydVgafWtNAx4w83UIGkQ='), nil)