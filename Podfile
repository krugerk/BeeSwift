# Uncomment this line to define a global platform for your project
platform :ios, '14.0'
use_frameworks!
inhibit_all_warnings!
target 'BeeSwift' do
	pod "Alamofire", '~> 4.9'
	pod "AlamofireImage", '~> 3.6'
	pod 'AlamofireNetworkActivityIndicator', '~> 2.4'
	pod 'SnapKit', '~> 4.0'
	pod "SwiftyJSON"	
	pod "MBProgressHUD"
	pod 'IQKeyboardManager'
end
target 'BeeSwiftToday' do
	pod 'Alamofire', '~> 4.9'
	pod 'AlamofireImage', '~>3.6'
	pod 'SnapKit', '~> 4.0'
	pod "SwiftyJSON"
	pod "MBProgressHUD"	
end
target 'BeeSwiftIntents' do
	pod 'Alamofire', '~> 4.9'
	pod 'SwiftyJSON'
end
target 'BeeSwiftTests' do
	pod "Alamofire", '~> 4.9'
	pod "AlamofireImage", '~> 3.6'
	pod 'AlamofireNetworkActivityIndicator', '~> 2.4'
	pod 'SnapKit', '~> 4.0'
	pod "SwiftyJSON"
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = '5.0'
      config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
