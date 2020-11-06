Pod::Spec.new do |s|
  s.name             = 'ios-sdk'
  s.version          = '0.0.1'
  s.summary          = 'Fastrean SDK for iOS'
  s.description      = <<-DESC
  Fastrean SDK for iOS
                       DESC

  s.homepage         = 'https://github.com/Fastream/ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'lukasz7251' => 'lukasz.szymanczuk@fastream.io' }
  s.source           = { :git => 'https://github.com/Fastream/ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'ios-sdk/Classes/**/*'
  
end
