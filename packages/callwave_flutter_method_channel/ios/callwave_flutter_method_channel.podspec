Pod::Spec.new do |s|
  s.name             = 'callwave_flutter_method_channel'
  s.version          = '0.1.0'
  s.summary          = 'MethodChannel implementation for callwave_flutter.'
  s.description      = <<-DESC
MethodChannel implementation for callwave_flutter.
                       DESC
  s.homepage         = 'https://github.com/callwave/callwave_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Callwave' => 'dev@callwave.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'CallKit', 'AVFAudio'
  s.static_framework = true
end
