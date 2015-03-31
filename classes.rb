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
    db = Database.new
    db.write_to_database(Time.new, 'client', false, message.user.name, message.message)
  end

  def register_private_message(message)
    db = Database.new
    db.write_to_database(Time.new, 'private', true, message.user.name, message.message)
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
  attr_accessor :database_path

  def initialize(database_url)
    # check if database was used before, otherwise generate what we need
    puts 'init started'
    @DB
    @messages_ds
    @keys_ds
    @database_path = database_url

    if !File.exist?(File.basename(database_url))
      setup_message_database
      setup_key_database
    end

    @DB = Sequel.connect(@database_path)
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
    # write key to key database and register it as a new column in the messages database
    @keys_ds.insert(:description => description, :host => host, :private_key => private_key, :public_key => public_key)

  end

  def hash_key(public_key)
    Base64.encode64(Digest::SHA256.digest public_key)
  end



  private
  def setup_message_database
    puts 'setting up db...'
    @DB = Sequel.sqlite
    @DB = Sequel.connect(@database_path)
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
    puts 'setting up key database'
    @DB = Sequel.sqlite
    @DB = Sequel.connect(@database_path)
    @DB.create_table? :keys do
      primary_key :id  # id
      String :description  # description of the respective key
      String :host  # contains url / whatever of the host
      String :private_key  # only contains a value if it's a local private key, otherwise nil
      String :public_key  # contains public key of respectiv host
    end
  end

  def add_new_messages_column(public_key)
    new_column_title = Base64.encode64(hash_key(public_key))
    @messages_ds.add_column(:new_column_title.to_sym)
  end
end

class CryptoBox
  # attr_writer :pri  vate_key, :public_key
  attr_accessor :private_key, :public_key

  def initialize
    @public_key
    @private_key
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

db = DatabaseBox.new('sqlite://test.db')
db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)
db.read_messages_from_database
puts db.hash_key 'hurz'