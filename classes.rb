require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'time'
require 'sequel'
require 'nacl'
require 'securerandom'
require 'sqlite3'
require 'digest'
require 'base64'

$dbpath = "sqlite://test.db"

class Logger
  include Cinch::Plugin

  listen_to :private,    :method => :register_private_message
  listen_to :disconnect, :method => :disco
  listen_to :channel,    :method => :register_public_message

  def initialize(*args)
    super
    @short_format = "%Y-%m-%d"
    @long_format = "%Y-%m-%d %H:%M:%S"
  end
 
  def disco(*)
    puts 'got disconnected'
  end
 
  # registers a public message on the channel
  def register_public_message(message)
    db = DatabaseBox.new
    db.write_message_to_database(Time.new, 'client', false, message.user.name, message.message, nil)
  end

  def register_private_message(message)
    db = DatabaseBox.new
    db.write_message_to_database(Time.new, 'private', true, message.user.name, message.message, nil)
    #puts "#{Time.new} #{message.user.name} whispers: #{message.message}"
  end

end

class RelayChat
  def initialize(nick, realname, server, channels)
    bot = Cinch::Bot.new do
    configure do |c|
      c.nick = nick
      c.realname = realname
      c.server = server
      c.channels = [channels]
      c.plugins.plugins = [Logger]
    end
    end
    bot.start

    def send_message(nick, recipient)
    # sends a private message to the desired nick
    puts 'virtual message'

  end
  end
end

class DatabaseBox  # todo: rewrite DatabaseBox to be a more generic accessor for databases
  attr_reader :messages_ds  # make dataset readable
  def initialize
    # check if database was used before, otherwise generate what we need
    @DB
    @messages_ds
    @keys_ds

    #if !File.exist?(File.basename($dbpath))
      setup_message_database
      setup_key_database
    #end

    @DB = Sequel.connect($dbpath)
    @messages_ds = @DB[:messages]  # create dataset for messages
    @keys_ds = @DB[:keys]  # create dataset for keys

  end

  def write_message_to_database(timestamp, client, private, sender, message, attachment)
    # write the message from the client application to the database
    @messages_ds.insert(:time => timestamp, :client => client, :private => private, :sender => sender, :message => message, :attachment => attachment)
  end

  def read_messages_from_database()
    # read a message from database
    # puts @messages_ds.all
    # puts @messages_ds.get(:time)
    # puts @messages_ds.each{|x| p x.name}
  end

  def register_key (description, host, private_key, public_key)
    @keys_ds.insert(:description => description, :host => host, :private_key => private_key, :public_key => public_key, :revoked => false)
  end

  def revoke_key(public_key)
    @keys_ds.where(:public_key=>public_key).update(:revoked=>true)
    puts @keys_ds.where(:public_key=>public_key).to_a
  end

  def output_host_keypair
    found_keypairs = @keys_ds.exclude(:private_key=>nil).exclude(:revoked=>true).to_a
    if found_keypairs.length < 1
      # no keypair found. have to generate one
      # todo: generate keypair
      crypto = CryptoBox.new  # todo: put host key generation somewhere else where it makes sense and is executed not just by accident
      public_key, private_key = crypto.generate_keypair
      register_key('host', '127.0.0.1', private_key, public_key)
    elsif found_keypairs.length == 1
      # exactly one keypair found. returning it
      [found_keypairs[0][:public_key], found_keypairs[0][:private_key]]
    elsif found_keypairs.length > 1
      # there's more than one valid hostkey in the database. something went terribly wrong
      # todo: think about handling it; maybe delete every host key present
      # todo: implement helpful logging
      puts 'there is more then one valid host key present, database corrupt. data breach?'
    end
  end

  def output_all_keys
    pubkey_array = []
    found_keys = @keys_ds.where(:revoked=>false).where(:private_key=>nil).to_a
    found_keys.each do |element|
      pubkey_array << [element[:public_key]]
    end
    pubkey_array
  end

  def check_for_revocation(key_id)
    # takes a key_id and looks it up in the keystore database table. Returns true if revoked, false if not revoked
    key_hash = @keys_ds.where(:id=>key_id).to_a
    key_hash[0][:revoked]
  end
end


  private

  def hash_key(public_key)
    Base64.encode64(Digest::SHA256.digest public_key)
  end

  def setup_message_database
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :messages do
      primary_key :id  # wtf
      Datetime :time  # time when the message was received
      String :client  # client (hazewood_irc, juforum_xmpp...)
      TrueClass :private  # true if the message is private (for IRC, e.g.)
      String :sender  # client specific sender of the message
      String :message  # message; only to use if it's clear that it's just a string!
      File :attachment  # to save images and complete emails
    end
    @messages_ds = @DB[:message]  # dataset creation
    @DB.disconnect
  end

  def setup_key_database
    # sets up the key table and the nonce database
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :keys do
      primary_key :id  # id
      String :description  # description of the respective key
      String :host  # contains url / whatever of the host
      String :private_key  # only contains a value if it's a local private key, otherwise nil
      String :public_key  # contains public key of respectiv host
      TrueClass :revoked  # false if the key is revoked
    end

  end

class EncryptedAdapter
  def initialize

  end

  def write_encrypted_message(timestamp, client, private_bool, sender, message, attachment)
    # a drop-in encryption-enabling wrapper for DatabaseBox
    # encrypts every message's sender, message and attachments with every single pubkey in the key database
    database = DatabaseBox.new
    crypto = CryptoBox.new
    database.output_all_keys.each do |public_key|

      database.write_message_to_database(timestamp, client, private_bool, crypto.encrypt_sting(sender, public_key), crypto.encrypt_sting(message, public_key), crypto.encrypt_sting(attachment, public_key))
    end

    # crypto.encrypt_sting(sender, )
    # database.write_message_to_database(timestamp, client, private_bool, enc_sender, enc_message, enc_attachment)

  end
end

class CryptoBox
  # attr_writer :pri  vate_key, :public_key
  attr_accessor :private_key, :public_key

  def initialize
    database = DatabaseBox.new
    # pub_key, priv_key = database.output_host_keypair
    @public_key #= pub_key
    @private_key #= priv_key
  end

  def testing_generate_receiving_keypair
    db = DatabaseBox.new
    pub, priv = NaCl.crypto_box_keypair
    db.register_key('example description', 'horst', nil, pub)
  end

  def generate_keypair
    @public_key, @private_key = NaCl.crypto_box_keypair
  end

  def encrypt_sting(string_to_encrypt, receiver_key)
    nonce = SecureRandom.random_bytes(NaCl::BOX_NONCE_LENGTH)
    cipher_text = NaCl.crypto_box(string_to_encrypt, nonce, receiver_key, @private_key)
    [cipher_text, nonce]
  end

  def decrypt_string(string_to_decrypt, sender_key, nonce)
    NaCl.crypto_box_open(string_to_decrypt, nonce, sender_key, @private_key)
  end

end
