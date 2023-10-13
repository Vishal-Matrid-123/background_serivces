import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled1/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage? message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await setupFlutterNotifications();
  showFlutterNotification(message!);
  String time = DateTime.now().toUtc().toIso8601String();
  saveNotifications(
    notificationData: jsonEncode(
      {
        'ImageUrl': message.notification!.android!.imageUrl,
        'TimeStamp': time,
        'Description': message.notification!.body,
        'Title': message.notification!.title,
        'CreatedOn': time,
      },
    ),
  );
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  print('Handling a background message ${message.messageId}');
}

/// Create a [AndroidNotificationChannel] for heads up notifications
late AndroidNotificationChannel channel;

bool isFlutterLocalNotificationsInitialized = false;

Future<void> setupFlutterNotifications() async {
  if (isFlutterLocalNotificationsInitialized) {
    return;
  }
  channel = const AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title

    description: 'This channel is used for important notifications.',
    // description
    importance: Importance.high,
  );

  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Create an Android Notification Channel.
  ///
  /// We use this channel in the `AndroidManifest.xml` file to override the
  /// default FCM channel to enable heads up notifications.
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  /// Update the iOS foreground notification presentation options to allow
  /// heads up notifications.
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  isFlutterLocalNotificationsInitialized = true;
}

void showFlutterNotification(RemoteMessage message) {
  RemoteNotification? notification = message.notification;
  AndroidNotification? android = message.notification?.android;
  if (notification != null && android != null && !kIsWeb) {
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          // TODO add a proper drawable resource to android, for now using
          //      one that already exists in example app.
          icon: 'ic_stat_notifications_active',
        ),
      ),
    );
  }
}

void saveNotifications({required String notificationData}) async {
  try {
    final url =
        Uri.parse('https://www.theone.com/ApisSecondVer/AddNewNotification?');

    final response = await post(url, body: {'notification': notificationData});

    if (kDebugMode) {
      print(response.body);
    }
  } catch (e) {
    if (kDebugMode) {
      print(e.toString());
    }
  }
}

/// Initialize the [FlutterLocalNotificationsPlugin] package.
late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

Future<void> setFireStoreData(
  RemoteMessage message,
) async {
  print('Checking Notification');
  final reference =
      FirebaseFirestore.instance.collection('THE_One_Staging_Notifications');
  String imageUrlIOS = Platform.isIOS
      ? message.notification!.apple!.imageUrl ?? ''
      : message.notification!.android!.imageUrl ?? '';

  String notificationDesc = message.notification?.body ?? '';
  String notificationTitle = message.notification?.title ?? '';

  bool isAlreadyExisted = false;
  QuerySnapshot query = await reference
      .where('Title', isEqualTo: message.notification!.title)
      .get();
  if (query.docs.length > 0) {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> list =
        query.docs as List<QueryDocumentSnapshot<Map<String, dynamic>>>;

    for (QueryDocumentSnapshot<Map<String, dynamic>> element in list) {
      String title = element['Title'];
      String desc = element['Desc'];
      Timestamp time = element['Time'];
      print('Time Difference Id>>>>' +
          DateTime.now().difference(time.toDate()).inHours.toString());

      if (title.toLowerCase().contains(notificationTitle.toLowerCase()) &&
          DateTime.now().difference(time.toDate()).inHours < 6 &&
          desc.toLowerCase().contains(notificationDesc.toLowerCase())) {
        isAlreadyExisted = true;

        print('Existed');
        break;
      } else {
        print('Not Existed');
      }
    }

    // the ID exists
  }

  Map<String, dynamic> data = {
    'Title': message.notification!.title,
    'Desc': message.notification!.body,
    'Time': Timestamp.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch),
    'Image': imageUrlIOS
  };

  if (isAlreadyExisted == true) {
  } else {
    reference.doc().set(data).whenComplete(() => print('Saved'));
  }
  // reference.doc().set(data);
}

@pragma('vm:entry-point')
Future<void> _messageHandler(RemoteMessage message) async {
  setFireStoreData(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);

  await initializeService();
  FlutterBackgroundService().invoke('setAsBackground');
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging.onMessage.listen(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging.onMessageOpenedApp
      .listen(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission();
  String token = await FirebaseMessaging.instance
          .getToken(vapidKey: 'AIzaSyBoMLFhJ8ir_pT57X1qFtmYSS-CQQzoXuE') ??
      '';

  runApp(
    MyApp(
      fcmToken: token,
    ),
  );
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'my_foreground', // id
    'MY FOREGROUND SERVICE', // title

    description: 'This channel is used for important notifications.',
    // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString('hello', 'world');

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) async {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  if (service is AndroidServiceInstance) {
    if (await service.isForegroundService()) {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_firebaseMessagingBackgroundHandler);
    } else {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_firebaseMessagingBackgroundHandler);
    }
  }
  // bring to foreground
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    FirebaseMessaging.onMessage.listen((event) {
      _firebaseMessagingBackgroundHandler(event);
    });

    // test using external plugin
    final deviceInfo = DeviceInfoPlugin();
    String? device;
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      device = androidInfo.model;
    }

    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      device = iosInfo.model;
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key, required this.fcmToken}) : super(key: key);
  final String fcmToken;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String text = 'Stop Service';

  @override
  void didChangeDependencies() {
    FirebaseMessaging.onMessage.listen((event) {
      _firebaseMessagingBackgroundHandler(event);
    });
    super.didChangeDependencies();
  }

  Future <List<Map<String, dynamic>>> _data = returnNotifications();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Service App'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _data,
            builder: (context, snapshot) {
              return snapshot.hasData && snapshot.data != null
                  ? ListView(children: [
                      TextButton(
                          onPressed: () {
                           _data =  returnNotifications();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('Refresh Future Builder'),
                          )),
                      SelectableText(widget.fcmToken),
                      ...List.generate(
                          snapshot.data!.length,
                          (index) => Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(snapshot.data![index]['Title']),
                              )),
                    ])
                  : snapshot.hasError
                      ? Center(
                          child: Text(snapshot.error.toString()),
                        )
                      : const Center(child: CircularProgressIndicator());
            }),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            FlutterBackgroundService().invoke('setAsBackground');
          },
          child: const Icon(Icons.play_arrow),
        ),
      ),
    );
  }
}

class LogView extends StatefulWidget {
  const LogView({Key? key}) : super(key: key);

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  late final Timer timer;
  List<String> logs = [];

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.reload();
      logs = sp.getStringList('log') ?? [];
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs.elementAt(index);
        return Text(log);
      },
    );
  }
}

Future<List<Map<String, dynamic>>> returnNotifications() async {
  String url = 'https://www.theone.com/ApisSecondVer/GetAllNotification';
  final uri = Uri.parse(url);
  final response = await get(uri);
  return returnMappedList(data: jsonDecode(response.body)['ResponseData']);
}

List<Map<String, dynamic>> returnMappedList({required List<dynamic> data}) {
  return List<Map<String, dynamic>>.from(data.map((e) => e));
}
