require "harness"
require "spec_helper"
include BVT::Spec

describe BVT::Spec::ImageMagicKSupport::Java do

  before(:all) do
    @session = BVT::Harness::CFSession.new
  end

  after(:each) do
    @session.cleanup!
  end

  it "Deploy Java 6 Spring application that uses ImageMagick tools" do
    app = create_push_app("spring_imagemagick_java6")
    app.get_response(:get).body_str.should == "hello from imagemagick"
  end
end
