


Pod::Spec.new do |spec|
  spec.name         = "NeoSDKCall"
  spec.module_name  = "NeoSDKCall"
  spec.version      = "1.2.1-rc.9"
  spec.summary      = "SDK for calling app to app webrtc."
  spec.description  = <<-DESC
    CiCareSDKRTC is a SDK for calling app to app or app to phone via webrtc.
  DESC
  spec.homepage     = "https://github.com/rtckitteam/neo-sdk-call-ios"
  spec.license      = { :type => "Commercial", :file => "LICENSE" }
  spec.readme       = "https://raw.githubusercontent.com/rtckitteam/neo-sdk-call-ios/refs/heads/main/README.md"
  spec.author       = { "RTCKit Team" => "rtckitteam@gmail.com" }
  spec.platform     = :ios, "12.0"
  spec.swift_version = ['5.9', '5.10']

  # Source code SDK
  spec.source       = { :git => "https://github.com/rtckitteam/neo-sdk-call-ios.git", :tag => spec.version.to_s }

  # Jika menggunakan source code
  # spec.source_files = "Sources/NeoSdkCall/**/*.{swift,h,m,xcassets}"
  # spec.resources = ['Sources/NeoSdkCall/Media.xcassets']
  
  spec.source_files = "Sources/NeoSdkCall/**/*.{swift,h,m,xcassets}"
  spec.resource_bundles = {
    'NeoSDKCall' => ['Sources/NeoSdkCall/Media.xcassets']
  }


  # If use Framework binary
  # spec.vendored_frameworks = "Frameworks/MySDK.xcframework"

  # Dependencies (optional)
  spec.dependency "WebRTC-lib", "138.0.0"
  spec.dependency "Socket.IO-Client-Swift", "16.1.1"
  spec.dependency "Starscream", "4.0.8"
  spec.dependency "CryptoSwift", "1.8.4"
  
  # Build setting for module stability
  spec.static_framework = true
  spec.pod_target_xcconfig = {
    "BUILD_LIBRARY_FOR_DISTRIBUTION" => "YES",
    "IPHONEOS_DEPLOYMENT_TARGET" => "12.0"
  }
end
