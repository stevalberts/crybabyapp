/*
 * Copyright 2023 The TensorFlow Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *             http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'helper/audio_classification_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('ic_launcher'); // Replace with your app icon name
  const DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // init notification
  await initializeNotifications();

  runApp(const AudioClassificationApp());
}

class AudioClassificationApp extends StatelessWidget {
  const AudioClassificationApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cry Baby App',
      theme: ThemeData(
        useMaterial3: false,
        primarySwatch: Colors.purple
      ),
      home: const MyHomePage(title: 'Cry Baby App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform =
      MethodChannel('org.tensorflow.audio_classification/audio_record');

  // The YAMNet/classifier model used in this code example accepts data that
  // represent single-channel, or mono, audio clips recorded at 16kHz in 0.975
  // second clips (15600 samples).
  static const _sampleRate = 16000; // 16kHz
  static const _expectAudioLength = 975; // milliseconds
  final int _requiredInputBuffer =
      (16000 * (_expectAudioLength / 1000)).toInt();
  late AudioClassificationHelper _helper;
  List<MapEntry<String, double>> _classification = List.empty();

  bool happy = false;
  bool cry = false;
  bool listen = false;
  var _showError = false;

  void _startRecorder() {
    try {
      platform.invokeMethod('startRecord');
    } on PlatformException catch (e) {
      log("Failed to start record: '${e.message}'.");
    }
  }

  Future<bool> _requestPermission() async {
    try {
      return await platform.invokeMethod('requestPermissionAndCreateRecorder', {
        "sampleRate": _sampleRate,
        "requiredInputBuffer": _requiredInputBuffer
      });
    } on Exception catch (e) {
      log("Failed to create recorder: '${e.toString()}'.");
      return false;
    }
  }

  Future<Float32List> _getAudioFloatArray() async {
    var audioFloatArray = Float32List(0);
    try {
      final Float32List result =
          await platform.invokeMethod('getAudioFloatArray');
      audioFloatArray = result;
    } on PlatformException catch (e) {
      log("Failed to get audio array: '${e.message}'.");
    }
    return audioFloatArray;
  }

  Future<void> _closeRecorder() async {
    try {
      await platform.invokeMethod('closeRecorder');
      _helper.closeInterpreter();
    } on PlatformException {
      log("Failed to close recorder.");
    }
  }

  @override
  initState() {
    _initRecorder();
    super.initState();
  }

  Future<void> _initRecorder() async {
    _helper = AudioClassificationHelper();
    await _helper.initHelper();
    bool success = await _requestPermission();
    if (success) {
      _startRecorder();

      Timer.periodic(const Duration(milliseconds: _expectAudioLength), (timer) {
        // classify here
        _runInference();
      });
    } else {
      // show error here
      setState(() {
        _showError = true;
      });
    }
  }

  Future<void> _runInference() async {
    Float32List inputArray = await _getAudioFloatArray();
    final result =
        await _helper.inference(inputArray.sublist(0, _requiredInputBuffer));
    setState(() {
      // take top 1 classification to detect one object
      _classification = (result.entries.toList()
            ..sort(
              (a, b) => a.value.compareTo(b.value),
            ))
          .reversed
          .take(1)
          .toList();

      var item = _classification.first;

      if (item.key == "Crying, sobbing" ||
          item.key == "Baby cry, infant cry" ||
          item.key == "Screaming") {
        cry = true;
        happy = false;
        listen = false;
      }else if(item.key == "Baby laughter"){
        cry = false;
        happy = true;
        listen = false;
      }else{
        cry = false;
        happy = false;
        listen = true;
      }
    });
  }

  void showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails('your_channel_id', 'Your Channel Name',
        channelDescription: 'Your channel description',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Flutter Notification',
        playSound: true);
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(0, 'Cry Baby App',
        "Alert! Baby is crying. :'(", platformChannelSpecifics);
  }


  @override
  void dispose() {
    _closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cry Baby App"),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_showError) {
      return const Center(
        child: Text(
          "Audio recording permission required for audio classification",
          textAlign: TextAlign.center,
        ),
      );
    } else {
      return Center(
        child: ListView.separated(
          padding: const EdgeInsets.all(10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: _classification.length,
          itemBuilder: (context, index) {
            final item = _classification[index];

            // Example if statement
            if (item.key == "Baby laughter") {
              print("I am happy!");
            } else if (item.key == "Crying, sobbing" ||
                item.key == "Baby cry, infant cry" ||
                item.key == "Screaming") {
              showNotification();
              print("I am crying.");
            } else {
              print("Listening....[${item.key}]");
            }
            print("===================");

            return Column(
              children: [
                Visibility(
                  visible: cry,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/images/crying.png',
                          height: 200,
                          width: 200,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          "Baby cry, infant cry",
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Visibility(
                  visible: happy,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/images/happy.png',
                          height: 200,
                          width: 200,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          "Baby laughter",
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Visibility(
                  visible: listen,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/images/confused.png',
                          height: 200,
                          width: 200,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Text(
                              "Listening...",
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(item.key),
                            ),
                            // Padding(
                            //   padding: const EdgeInsets.all(8.0),
                            //   child: Row(
                            //     children: [
                            //       Flexible(
                            //         child: LinearProgressIndicator(
                            //           backgroundColor: Colors.blue.shade100,
                            //           color: Colors.blue.shade400,
                            //           value: item.value,
                            //           minHeight: 10,
                            //           borderRadius: BorderRadius.circular(8.0),
                            //         ),
                            //       ),
                            //     ],
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            );
          },
          separatorBuilder: (BuildContext context, int index) => const SizedBox(
            height: 10,
          ),
        ),
      );
    }
  }
}
