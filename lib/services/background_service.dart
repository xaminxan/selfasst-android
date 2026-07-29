import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'background_poller.dart';

const String _channelId = 'genericagent_bg_service';
const String _channelName = 'GenericAgent 后台服务';
const String _channelDesc = '保持 GenericAgent 后台运行以接收消息';

/// Initialize the foreground service so the poller timer survives
/// Android background execution limits.
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // Android notification channel for the persistent "service is running" notification
  final androidNotificationChannel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDesc,
    importance: Importance.low, // low importance so it's not intrusive
    playSound: false,
    enableVibration: false,
  );

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidNotificationChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _backgroundTask, // must be a top-level function
      notificationChannelId: _channelId,
      initialNotificationTitle: 'GenericAgent',
      initialNotificationContent: '消息监控中',
      foregroundServiceNotificationId: 888,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: _onIosForeground,
      onBackground: _onIosBackground,
    ),
  );

  // Start the service immediately.
  await service.startService();
}

/// Top-level callback for iOS foreground — no-op, just returns.
void _onIosForeground(ServiceInstance service) {}

/// Top-level callback for iOS background — no-op, returns true.
Future<bool> _onIosBackground(ServiceInstance service) async => true;

/// Top-level callback that runs in the background isolate.
/// Starts the poller and listens for "stop" commands.
@pragma('vm:entry-point')
void _backgroundTask(ServiceInstance service) {
  // Only Android uses a foreground service notification.
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'GenericAgent',
      content: '消息监控中',
    );
  }

  // Start the existing poller — its Timer.periodic will now survive
  // backgrounding because the foreground service keeps the isolate alive.
  BackgroundPoller.start();

  // Listen for "stop" commands from the app (e.g. user toggles off).
  service.on('stop').listen((_) {
    BackgroundPoller.stop();
    service.stopSelf();
  });
}