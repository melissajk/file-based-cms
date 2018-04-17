# frozen_string_literal: true

require 'yaml'

require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'bcrypt'
require 'fileutils'

IMAGE_FILE_EXTENSIONS = %w[.jpeg .png .gif .jpg]

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_directory
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/', __FILE__)
  else
    File.expand_path('../', __FILE__)
  end
end

def data_file_path(file_name)
  "#{data_directory}/#{file_name}"
end

def data_path
  data_file_path('data')
end

def credentials_path
  data_file_path('users.yml')
end

def load_user_credentials
  YAML.load_file(credentials_path) || {}
end

def image_path
  directory = ENV['RACK_ENV'] == 'test' ? 'uploads' : 'public/uploads'

  data_file_path(directory)
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    content
  when '.md'
    render_markdown(content)
  end
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  return if user_signed_in?
  session[:message] = 'You must be signed in to do that.'
  status 403
  redirect '/'
end

def valid_credentials?(username, password)
  users = load_user_credentials

  if users.key?(username)
    bcrypt_password = BCrypt::Password.new(users[username])
    bcrypt_password == password
  else
    false
  end
end

def signup_error(username, password1, password2)
  error_for_passwords(password1, password2) ||
  error_for_username(username)              ||
  nil
end

def error_for_passwords(password1, password2)
  if password1 != password2
    'Passwords do not match -- Please try again.'
  elsif password1.size < 6
    'Password must be at least 6 characters.'
  elsif password1.include?(' ')
    'Please provide a password with no spaces.'
  end
end

def error_for_username(username)
  users = load_user_credentials
  
  if username.strip.size < 4
    'Username must be at least 4 characters (no spaces)'
  elsif users.key?(username)
    'Username is taken -- Please choose another.'
  end
end

def next_version(base_filename)
  pattern = File.join(data_path, '*')

  files = Dir.glob(pattern).map do |path|
    File.basename(path, '.*')
  end

  files.select { |name| name.match(base_filename) }
       .map { |name| name.chars.last.to_i }.max + 1
end

def image?(file)
  IMAGE_FILE_EXTENSIONS.include?(File.extname(file).downcase)
end

get '/' do
  pattern = File.join(data_path, '*')

  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :index
end

get '/new' do
  require_signed_in_user

  erb :new_file
end

post '/new' do
  require_signed_in_user

  filename = params[:new_file].strip.to_s
  extension = params[:extension]

  if filename.size.zero?
    session[:message] = 'A name is required.'
    status 422
    erb :new_file
  else
    filename += extension

    file_path = File.join(data_path, filename)

    File.new(file_path, 'w')
    session[:message] = "#{filename} has been created."

    redirect '/'
  end
end

get '/images' do
  @images = Dir.glob(File.join(image_path, '*'))
  erb :images
end

post '/upload' do
  require_signed_in_user

  if params[:file] && image?(params[:file][:filename])
    tempfile = params[:file][:tempfile]
    filename = params[:file][:filename]
    
    target = File.join(image_path, filename)
    
    File.open(target, 'wb') { |f| f.write tempfile.read }

    session[:message] = "#{filename} has been uploaded."

  elsif params[:file]
    session[:message] = "File must be an image."
  else
    session[:message] = 'You must choose a file.'
  end
  redirect '/images'
end

get '/:filename' do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect '/'
  end
end

get '/:filename/edit' do
  require_signed_in_user

  @filename = params[:filename].to_s

  file_path = File.join(data_path, @filename)

  if File.file?(file_path)
    @content = File.read(file_path)
    @images = Dir.glob(File.join(image_path, '*'))
    erb :edit_file
  else
    session[:message] = "#{@filename} does not exist."
    redirect '/'
  end
end

post '/:filename/add-image/:image' do
  require_signed_in_user

  filename = params[:filename]
  image    = params[:image]

  file_path = File.join(data_path, filename)

  content = File.read(file_path) + "\n![image](/uploads/#{image})"

  File.write(file_path, content)

  session[:message] = "#{image} has been added to #{filename}."
  redirect "/#{filename}/edit"
end

post '/:filename/edit' do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated"
  redirect '/'
end

post '/:filename/delete' do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect '/'
end

post '/:filename/duplicate' do
  require_signed_in_user

  filepath = File.join(data_path, params[:filename].to_s)

  base_filename = File.basename(filepath, '.*').gsub(/_copy_[1-9]/, '')

  new_name = base_filename + "_copy_#{next_version(base_filename)}"

  new_filepath = File.join(data_path, new_name + File.extname(filepath))

  File.new(new_filepath, 'w')

  FileUtils.cp(filepath, new_filepath)

  session[:message] = "#{params[:filename]} has been duplicated."
  redirect '/'
end

get '/users/signin' do
  erb :sign_in
end

get '/users/signup' do
  erb :sign_up
end

post '/users/signin' do
  if valid_credentials?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = 'Invalid Credentials'
    status 422
    erb :sign_in
  end
end

post '/users/signup' do
  users = load_user_credentials

  error = signup_error(params[:username], params[:password], params[:verify_password])

  if error
    status 422
    session[:message] = error
    erb :sign_up
  else
    encrypted_password = BCrypt::Password.create(params[:password])

    users[params[:username]] = encrypted_password.to_s
    File.write(credentials_path, users.to_yaml)
    session[:username] = params[:username]
    session[:message] = "Welcome #{session[:username]}!"
    redirect '/'
  end
end

post '/users/signout' do
  session.delete(:username)
  session[:message] = 'You have been signed out'
  redirect '/'
end
