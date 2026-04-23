Pod::Spec.new do |s|
  s.name             = 'callwave_flutter_method_channel'
  s.version          = '0.2.0'
  s.summary          = 'MethodChannel implementation for callwave_flutter.'
  s.description      = <<-DESC
MethodChannel implementation for callwave_flutter.
                       DESC
  s.homepage         = 'https://github.com/Effdelorg/callwave_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'EFFDEL ENTERPRISE PRIVATE LIMITED'
  s.source           = { :path => '.' }
  s.source_files     = 'callwave_flutter_method_channel/Sources/callwave_flutter_method_channel/**/*.swift'
  s.resource_bundles = {
    'callwave_flutter_method_channel_privacy' => [
      'callwave_flutter_method_channel/Sources/callwave_flutter_method_channel/PrivacyInfo.xcprivacy'
    ]
  }
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'CallKit', 'AVFAudio', 'UserNotifications', 'UIKit'
  s.static_framework = true
end
