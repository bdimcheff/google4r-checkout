# google4r-checkout Rakefile

require 'rake'
require 'rake/testtask'
require 'rake/gempackagetask'
require 'rake/rdoctask'

desc 'Default: run all tests tests.'
task :default => :'test:all'

desc 'Runs all tests (alias of test:all)'
task :test => :'test:all'

# 
# File sets 
# 
RUBY_FILES  = FileList['lib/**/*.rb', 'lib/**/vendor/**'] 
RDOC_EXTRA  = FileList['README','LICENSE', 'CHANGES'] 
EXTRA_FILES = FileList['var/cacert.pem'] 

#
# Documentation
#

desc 'Generate documentation for the google4r library.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'docs'
  rdoc.title    = 'google4r/checkout'
  rdoc.main     = 'README'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files = RUBY_FILES + RDOC_EXTRA 
end

#
# Test, test, test! I love saying the word "test"!
#

namespace :test do
  desc 'Run all tests on the Google4R::Checkout::* classes.'
  task :all => [ :integration, :unit, :system ]

  desc 'Run unit tests on the Google4R::Checkout::* classes.'
  Rake::TestTask.new(:unit) do |t|
    t.libs << 'lib'
    t.pattern = 'test/unit/*_test.rb'
    t.verbose = true
  end

  desc 'Run integration tests on the Google4R::Checkout::* classes.'
  Rake::TestTask.new(:integration) do |t|
    t.libs << 'lib'
    t.pattern = 'test/integration/*_test.rb'
    t.verbose = true
  end

  desc 'Run system tests on the Google4R::Checkout::* classes.'
  Rake::TestTask.new(:system) do |t|
    t.libs << 'lib'
    t.pattern = 'test/system/*_test.rb'
    t.verbose = true
  end
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.platform = Gem::Platform::RUBY

    gem.name = "google4r-checkout"
    gem.summary = "Ruby library to access the Google Checkout service and implement notification handlers."
    gem.description = gem.summary
    gem.authors = ["Tony Chan", "Brandon Dimcheff"]

    gem.test_files = FileList['test/**/*_test.rb'] 

    gem.required_ruby_version = '>= 1.8.4'
    gem.autorequire = ''

    gem.add_dependency('money', '>= 1.7.1')
  end

rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
end

