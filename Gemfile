source 'https://rubygems.org'
gemspec
gem 'sbsm', '>= 1.3.7'

group :debugger do
	if RUBY_VERSION.match(/^1/)
		gem 'pry-debugger'
	else
		gem 'pry-byebug'
    gem 'pry-doc'
	end
end
