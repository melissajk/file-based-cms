ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms.rb"

class TestApp < Minitest::Test
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    FileUtils.mkdir_p(image_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end
  
  def session
    last_request.env["rack.session"]
  end
  
  def admin_session
    { "rack.session" => { username: "admin" } }
  end
  
  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm_rf(image_path)

    credentials_path = File.expand_path("../users.yml", __FILE__)
    users = YAML::load_file(credentials_path)
    users.delete("new_user")
    File.write(credentials_path, users.to_yaml)
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document "history.txt", "2015 - Ruby 2.3 released."

    get "/history.txt"
    
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "2015 - Ruby 2.3 released."
  end
  
  def test_document_not_found
    get "/notafile.ext"
    
    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist.", session[:message]
  end
  
  def test_viewing_markdown_documents
    create_document "/about.md", "<h1>Ruby is...</h1>"
    get "/about.md"
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end
  
  
  def test_editing_documents
    create_document "/changes.txt", "This space for rent."
    
    get "/changes.txt/edit" , {}, admin_session
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_editing_docs_signed_out
    create_document "/changes.txt", "This space for rent."
    
    get "/changes.txt/edit"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_updating_document
    post "/changes.txt/edit", { content: "new_content"} , admin_session
    
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated", session[:message]
    
    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new_content"
  end
  
  def test_updating_docs_signed_out
    post "/changes.txt/edit", { content: "new content" }
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_view_new_file_form
    get "/new", {}, admin_session
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit")
    assert_includes last_response.body, "<input"
  end
  
  def test_new_file_form_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_create_new_file
    post "/new", { new_file: "test", extension: ".txt" }, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been created.", session[:message]
    
    get "/"
    assert_includes last_response.body, "test.txt"
  end
  
  def test_create_new_file_signed_out
    post "/new", { new_file: "test", extension: ".txt"}
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_create_new_document_without_filename
    post "/new", { new_file: "" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end
  
  def test_delete_file
    create_document("test.txt")
    
    post "/test.txt/delete", {}, admin_session

    assert_equal 302, last_response.status
    assert_equal "test.txt has been deleted.", session[:message]
    
    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end
  
  def test_delete_file_signed_out
    create_document("test.txt")
    
    post "/test.txt/delete"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_signin_form
    get "users/signin"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit")
    assert_includes last_response.body, "<input"
  end
  
  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]
    
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end
  
  def test_signin_with_bad_credentials
    post "/users/signin", username: "test", password: "incorrect"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    
    assert_includes last_response.body, "Invalid Credentials"
  end
  
  def test_sign_out
    get "/", {}, {"rack.session" => {username: "admin"}}
    assert_includes last_response.body, "Signed in as admin"
    
    post "users/signout"
    get last_response["Location"]
    
    assert_nil session[:username]
    assert_includes last_response.body, "You have been signed out"
    assert_includes last_response.body, "Sign In"
  end
  
  def test_duplicate_file
    create_document("changes.txt", "testing 1, 2, 3")
    
    post "changes.txt/duplicate", {}, admin_session
    
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been duplicated.", session[:message]
    
    get "/"
    assert_includes last_response.body, "changes_copy_1.txt"
    
    get "/changes_copy_1.txt"
    assert_includes last_response.body, "testing 1, 2, 3"
  end
  
  def test_duplicate_file_signed_out
    create_document("changes.txt", "testing 1, 2, 3")
    
    post "changes.txt/duplicate"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_signup_form
    get "users/signup"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit")
    assert_includes last_response.body, "<input"
  end
  
  def test_signup
    post "/users/signup", username: "new_user", password: "shhhhh", verify_password: "shhhhh"
    assert_equal 302, last_response.status
    
    assert_equal "Welcome new_user!", session[:message]
    assert_equal "new_user", session[:username]
    
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as new_user"
  end
  
  def test_signup_with_repeat_username
    post "/users/signup", username: "admin", password: "secret", verify_password: "secret"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    
    assert_includes last_response.body, "Username is taken -- Please choose another."
  end
  
  def test_signup_with_two_different_passwords
    post "/users/signup", username: "new_user", password: "shhhhh", verify_password: "shhhhhh"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    
    assert_includes last_response.body, "Passwords do not match -- Please try again."
  end
  
  def test_signup_with_short_password
    post "/users/signup", username: "new_user", password: "shh", verify_password: "shh"
    
    assert_equal 422, last_response.status
    assert_nil session[:username]
    
    assert_includes last_response.body, "Password must be at least 6 characters."
  end
  
  def test_upload_image_form
    get "/images"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<input type="submit")
    assert_includes last_response.body, "<input"
  end
  
  def test_upload_image
    test_path = File.expand_path("..", __FILE__)
    test_image_path = File.join(test_path, "test_image.jpg")
  
    post "/upload", {file: Rack::Test::UploadedFile.new(test_image_path, "image/jpeg")}, admin_session
    
    assert_equal 302, last_response.status
    assert_equal "test_image.jpg has been uploaded.", session[:message]
    
    get last_response["Location"]
    
    assert_includes last_response.body, "test_image.jpg"
  end
  
  def test_upload_unsupported_file
    test_path = File.expand_path("..", __FILE__)
    test_image_path = File.join(test_path, "test_file.rtf")
  
    post "/upload", {file: Rack::Test::UploadedFile.new(test_image_path, "text/plain")}, admin_session
  
    assert_equal 302, last_response.status
    assert_equal "File must be an image.", session[:message]
  end
  
  def test_upload_image_no_filename
    post "/upload", {}, admin_session
    
    assert_equal 302, last_response.status
    assert_equal "You must choose a file.", session[:message]
  end
  
  def test_upload_image_signed_out
    post "/upload"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  def test_no_image_list_in_text_file
    create_document "/changes.txt", "This space for rent."
    
    get "/changes.txt/edit" , {}, admin_session
    
    assert_equal 200, last_response.status
    refute_includes last_response.body, "<h3>Add an Image</h3>"
    assert_includes last_response.body, "This space for rent."
  end
  
  def test_image_list_in_markdown_file
    create_document "/about.md", "<h1>Ruby is...</h1>"

    get "/about.md/edit", {}, admin_session
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
    assert_includes last_response.body, "<h3>Add an Image</h3>"
  end
  
  def test_add_image_to_file
    test_path = File.expand_path("..", __FILE__)
    test_image_path = File.join(test_path, "test_image.jpg")
  
    post "/upload", {file: Rack::Test::UploadedFile.new(test_image_path, "image/jpeg")}, admin_session
    
    create_document "/about.md", "<h1>Ruby is...</h1>"
    
    post "/about.md/add-image/test_image.jpg"
    
    assert_equal 302, last_response.status
    assert_equal "test_image.jpg has been added to about.md.", session[:message]
    
    get last_response["Location"]

    assert_includes last_response.body, "![image](/uploads/test_image.jpg)"
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end
  
  def test_add_image_to_file_signed_out
    create_document "/about.md", "<h1>Ruby is...</h1>"

    post "/about.md/add-image/test_image.jpg"
    
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
end

