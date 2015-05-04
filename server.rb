require 'sinatra'
require_relative 'classes.rb'

Thread.new do
  Starter.new
end

db = DatabaseBox.new
# require 'rack/ssl'
# use Rack::SSL

# get '/:user/time/since/:time' do
#   time = params[:time]
#   "#{Time.parse(time)}"
# end

get '/:user/:beginID/to/:endID' do
  content_type :json
  # todo: reimplement this in order to get an array of message ids to retrieve from database
end

get '/:user/since/:id' do
  content_type :json
  db.output_new_message_ids(params[:user], params[:id].to_i).to_json
end

get '/:user/all' do
  content_type :json
  db.output_all_message_ids_by_key_id(params[:user]).to_json
end

get '/:user/:message' do  # some day this should be protected with an auth key, but not necessary
  content_type :json
  db.output_message_by_id(params[:message], params[:user]).to_json
end

get '/key' do
  "#{Base64.encode64(db.output_host_public_key)}"
end