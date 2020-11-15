Pod::Spec.new do |s|
  s.name             = 'fastream-ios-sdk'
  s.version          = '0.0.5'
  s.summary          = 'Fastream SDK for iOS'
  s.description      = <<-DESC
  Fastream-iOS-SDK - an iOS Event Tracking Library
                       DESC

  s.homepage         = 'https://github.com/Fastream/ios-sdk'
  s.license          = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author           = { 'lukasz.szymanczuk' => 'lukasz.szymanczuk@fastream.io' }
  s.source           = { :git => 'https://github.com/Fastream/ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'ios-sdk/Classes/**/*'
  
end
