require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "/documents/show.html.haml" do
  include DocumentsHelper
  
  before(:each) do       
    @document = Factory(:document)
    @document.user = Factory(:user)
    assigns[:document] = @document
  end

  it "should render attributes in <p>" do
    render "/documents/show.html.haml"
    response.should have_text(/#{@document.name}/)
    response.should have_text(/#{@document.description}/)
  end
end

