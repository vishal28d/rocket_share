import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:rocket_share/components/snackbar.dart';
import 'package:rocket_share/methods/methods.dart';
import 'package:rocket_share/models/sender_model.dart';
import 'package:rocket_share/services/device_service.dart';
import 'package:rocket_share/services/file_services.dart';
import '../controllers/controllers.dart';
import 'package:get_it/get_it.dart';

class PhotonReceiver {
  static late int _secretCode;
  static late Map<String, dynamic> filePathMap;
  static final Box _box = Hive.box('appData');
  static late int id;
  static int totalTime = 0;
  static final dio = Dio();

  /// to get network address [assumes class C address]
  static List<String> getNetAddress(List<String> ipList) {
    List<String> netAdd = [];
    for (String ip in ipList) {
      var ipToList = ip.split('.');
      ipToList.removeLast();
      netAdd.add(ipToList.join('.'));
    }
    return netAdd;
  }

  /// tries to establish socket connection
  static Future<Map<String, dynamic>> _connect(String host, int port) async {
    try {
      var socket = await Socket.connect(host, port)
          .timeout(const Duration(milliseconds: 2500));
      socket.destroy();
      return {"host": host, 'port': port};
    } catch (_) {
      return {};
    }
  }

  /// check if ip & port pair represent photon-server
  static isPhotonServer(String ip, String port) async {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final SecurityContext scontext = SecurityContext();
        HttpClient client = HttpClient(context: scontext);
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          return host == ip && port == 4040;
        };
        return client;
      },
    );
    var resp = await dio
        .get('${DeviceService.protocolFromSender}://$ip:$port/photon-server');
    Map<String, dynamic> senderInfo = jsonDecode(resp.data);
    return SenderModel.fromJson(senderInfo);
  }

  /// scan presence of photon-server[driver func]
  static Future<List<SenderModel>> scan() async {
    List<Future<Map<String, dynamic>>> list = [];
    List<SenderModel> photonServers = [];
    List<String> netAddresses = getNetAddress(await getIP());
    for (int i = 2; i < 255; i++) {
      //scan all of the wireless interfaces available
      for (String netAddress in netAddresses) {
        Future<Map<String, dynamic>> res = _connect('$netAddress.$i', 4040);
        list.add(res);
      }
    }

    for (var ele in list) {
      Map<String, dynamic> item = await ele;
      if (item.containsKey('host')) {
        Future<dynamic> resp;
        if ((resp = (isPhotonServer(
                item['host'].toString(), item['port'].toString()))) !=
            null) {
          photonServers.add(await resp);
        }
      }
    }
    list.clear();
    return photonServers;
  }

  static Future<List<SenderModel>> scanWithLegacyFallback() async {
    var resp = await scanV2();
    if (resp.isEmpty) {
      return await scan();
    }
    return resp;
  }

  static Future<List<SenderModel>> scanV2() async {
    DeviceService deviceService = DeviceService.getDeviceService();
    List<BonsoirService?> discoveredServices = await deviceService.discover();
    List<Future<Map<String, dynamic>>> list = [];
    List<SenderModel> photonServers = [];
    List<SenderModel> uniquePhotonServers = [];
    Set set = {};
    Map<String, dynamic> hostToProtocolMapping = {};
    for (var service in discoveredServices) {
      String? ip = service?.attributes["ip"];
      String? httpsEnabled = service?.attributes["https_enabled"];
      if (ip != null) {
        hostToProtocolMapping[ip] = httpsEnabled;
        Future<Map<String, dynamic>> res = _connect(ip, 4040);
        list.add(res);
      }
    }
    for (var ele in list) {
      Map<String, dynamic> item = await ele;
      if (item.containsKey('host')) {
        var httpsEnabled = hostToProtocolMapping[item["host"]];
        if (httpsEnabled == "true") {
          _box.put("protocol_from_sender", "https");
        } else {
          _box.put("protocol_from_sender", "http");
        }
        Future<dynamic> resp;
        if ((resp = (isPhotonServer(
                item['host'].toString(), item['port'].toString()))) !=
            null) {
          var val = await resp;
          if (!photonServers.contains(val)) {
            photonServers.add(val);
          }
        }
      }
    }
    list.clear();
    for (var item in photonServers) {
      if (!set.contains(item.ip)) {
        uniquePhotonServers.add(item);
        set.add(item.ip);
      }
    }
    return uniquePhotonServers;
  }

  static isRequestAccepted(SenderModel senderModel) async {
    String username = _box.get('username');
    var avatar = await rootBundle.load(_box.get('avatarPath'));
    var resp = await dio.get(
      '${DeviceService.protocolFromSender}://${senderModel.ip}:${senderModel.port}/get-code',
      options: Options(headers: {
        'receiver-name': username,
        'os': Platform.operatingSystem,
        'avatar': avatar.buffer.asUint8List().toString()
        // 'avatar': avatar.buffer.asUint8List().toString()s
      }),
    );
    id = Random().nextInt(10000);
    var senderRespData = jsonDecode(resp.data);
    return senderRespData;
  }

  static sendBackReceiverRealtimeData(SenderModel senderModel, token,
      {fileIndex = -1, isCompleted = true}) {
    try {
      dio.post(
          '${DeviceService.protocolFromSender}://${senderModel.ip}:4040/receiver-data',
          options: Options(
            headers: {
              "receiverID": id.toString(),
              "os": Platform.operatingSystem,
              "hostName": _box.get('username'),
              "currentFile": '${fileIndex + 1}',
              "isCompleted": '$isCompleted',
              "Authorization": token,
            },
          ));
    } catch (e) {
      rethrow;
    }
  }

  static receiveText(SenderModel senderModel, int secretCode, token) async {
    RawTextController getInstance = GetIt.instance.get<RawTextController>();
    var resp = await dio.get(
        "${DeviceService.protocolFromSender}://${senderModel.ip}:4040/$secretCode/text",
        options: Options(headers: {
          "Authorization": token,
        }));
    String text = jsonDecode(resp.data)['raw_text'];
    getInstance.rawText.value = text;
  }

  static receiveFolder(SenderModel senderModel, int secretCode,
      String? parentDirectory, token) async {
    PercentageController getInstance =
        GetIt.instance.get<PercentageController>();
    String filePath = '';
    totalTime = 0;
    try {
      var resp = await dio.get(
          '${DeviceService.protocolFromSender}://${senderModel.ip}:${senderModel.port}/getpaths',
          options: Options(headers: {
            "Authorization": token,
          }));
      filePathMap = jsonDecode(resp.data);
      _secretCode = secretCode;
      for (int fileIndex = 0;
          fileIndex < filePathMap['paths']!.length;
          fileIndex++) {
        //if a file is cancelled once ,it should not be automatically fetched without user action
        if (getInstance.isCancelled[fileIndex].value == false) {
          getInstance.fileStatus[fileIndex].value = Status.downloading.name;

          if (filePathMap.containsKey('isApk')) {
            if (filePathMap['isApk']) {
              // when sender sends apk files
              // this case is not true when sender sends apk from generic file selection
              filePath =
                  '${filePathMap['paths'][fileIndex].toString().split("/")[4].split("-").first}.apk';
            } else {
              filePath = filePathMap['paths'][fileIndex];
            }
          } else {
            filePath = filePathMap['paths'][fileIndex];
          }

          var temp = parentDirectory!
              .split(senderModel.os == "windows" ? r'\' : '/')
              .last;

          String senderPathSeparator = senderModel.os == "windows" ? r'\' : '/';
          final String newDirectory =
              "$temp/${filePath.split(filePath.split(senderPathSeparator).last).first.split(parentDirectory + senderPathSeparator).last}";
          await getFile(filePath, fileIndex, token, senderModel,
              parentDirectory: newDirectory, isDirectory: true);
        }
      }
      // sends after last file is sent
      sendBackReceiverRealtimeData(senderModel, token);
      getInstance.isFinished.value = true;
      getInstance.totalTimeElapsed.value = totalTime;
    } catch (e) {
      debugPrint('$e');
    }
  }

  static receiveFiles(SenderModel senderModel, int secretCode, token) async {
    PercentageController getInstance =
        GetIt.instance.get<PercentageController>();
    //getting hiveObj

    String filePath = '';
    totalTime = 0;
    try {
      var resp = await dio.get(
          '${DeviceService.protocolFromSender}://${senderModel.ip}:${senderModel.port}/getpaths',
          options: Options(headers: {
            "Authorization": token,
          }));
      filePathMap = jsonDecode(resp.data);
      _secretCode = secretCode;
      for (int fileIndex = 0;
          fileIndex < filePathMap['paths']!.length;
          fileIndex++) {
        //if a file is cancelled once ,it should not be automatically fetched without user action
        if (getInstance.isCancelled[fileIndex].value == false) {
          getInstance.fileStatus[fileIndex].value = Status.downloading.name;

          if (filePathMap.containsKey('isApk')) {
            if (filePathMap['isApk']) {
              // when sender sends apk files
              // this case is not true when sender sends apk from generic file selection
              filePath =
                  '${filePathMap['paths'][fileIndex].toString().split("/")[4].split("-").first}.apk';
            } else {
              filePath = filePathMap['paths'][fileIndex];
            }
          } else {
            filePath = filePathMap['paths'][fileIndex];
          }
          await getFile(filePath, fileIndex, token, senderModel);
        }
      }
      // sends after last file is sent

      sendBackReceiverRealtimeData(senderModel, token);
      getInstance.isFinished.value = true;
      getInstance.totalTimeElapsed.value = totalTime;
    } catch (e) {
      debugPrint('$e');
    }
  }

  static receive(SenderModel senderModel, int secretCode, String type,
      {String? parentDirectory = "", String? token}) async {
    switch (type) {
      case "raw_text":
        receiveText(senderModel, secretCode, token);
        break;
      case "folder":

        /// logic to handle folder share due to limited file system permission
        /// falls back to files share
        // if (senderModel.os.toString().toLowerCase() == 'android') {
        //   // since android is sending cached file paths
        //   // real folder structure cannot be reconstructed
        //   // receive files without preserving folder structure
        //   receiveFiles(senderModel, secretCode);
        //   break;
        // }
        receiveFolder(senderModel, secretCode, parentDirectory, token);
        break;
      default:
        receiveFiles(senderModel, secretCode, token);
        break;
    }
  }

  static getFile(
    String filePath,
    int fileIndex,
    String? token,
    SenderModel senderModel, {
    String parentDirectory = "",
    bool isDirectory = false,
  }) async {
    PercentageController getInstance = GetIt.I<PercentageController>();
    // creates instance of cancelToken and inserts it to list
    getInstance.cancelTokenList.insert(fileIndex, CancelToken());
    String dirPath =
        await FileUtils.getDirectorySavePath(senderModel, parentDirectory);
    if (parentDirectory.isNotEmpty) {
      if (!Directory(dirPath).existsSync()) {
        await Directory(dirPath).create(recursive: true);
      }
    }
    late String savePath;
    try {
      savePath = await FileUtils.getSavePathForReceiving(filePath, senderModel,
          isDirectory: isDirectory, directoryPath: dirPath);
    } catch (e) {
      getInstance.fileStatus[fileIndex].value = "cancelled";
      getInstance.isCancelled[fileIndex].value = true;
      return;
    }
    Stopwatch stopwatch = Stopwatch();
    int? prevBits;
    int? prevDuration;
    // for handling speed update frequency
    int count = 0;
    try {
      // sends post request every time receiver requests for a file
      sendBackReceiverRealtimeData(senderModel, token,
          fileIndex: fileIndex, isCompleted: false);
      stopwatch.start();
      getInstance.fileStatus[fileIndex].value = "downloading";
      await dio.download(
        '${DeviceService.protocolFromSender}://${senderModel.ip}:4040/$_secretCode/$fileIndex',
        options: Options(headers: {
          "Authorization": token,
        }),
        savePath,
        deleteOnError: true,
        cancelToken: getInstance.cancelTokenList[fileIndex],
        onReceiveProgress: (received, total) {
          if (total != -1) {
            count++;
            getInstance.percentage[fileIndex].value =
                (double.parse((received / total * 100).toStringAsFixed(0)));
            if (prevBits == null) {
              prevBits = received;
              prevDuration = stopwatch.elapsedMicroseconds;
              getInstance.minSpeed.value = getInstance.maxSpeed.value =
                  ((prevBits! * 8) / prevDuration!);
            } else {
              prevBits = received - prevBits!;
              prevDuration = stopwatch.elapsedMicroseconds - prevDuration!;
            }
          }
          //used for reducing speed update frequency
          if (count % 10 == 0) {
            getInstance.speed.value = (prevBits! * 8) / prevDuration!;
            //calculate min and max speeds
            if (getInstance.speed.value > getInstance.maxSpeed.value) {
              getInstance.maxSpeed.value = getInstance.speed.value;
            } else if (getInstance.speed.value < getInstance.minSpeed.value) {
              getInstance.minSpeed.value = getInstance.speed.value;
            }

            // update estimated time
            getInstance.estimatedTime.value = getEstimatedTime(
                received * 8, total * 8, getInstance.speed.value);
            //update time elapsed
          }
        },
      );
      totalTime = totalTime + stopwatch.elapsed.inSeconds;
      stopwatch.reset();
      getInstance.speed.value = 0.0;
      //after completion of download mark it as true
      getInstance.isReceived[fileIndex].value = true;
      storeHistory(_box, savePath);
      getInstance.fileStatus[fileIndex].value = "downloaded";
    } catch (e) {
      getInstance.speed.value = 0;
      getInstance.fileStatus[fileIndex].value = "cancelled";
      getInstance.isCancelled[fileIndex].value = true;

      if (!CancelToken.isCancel(e as DioException)) {
        debugPrint("Dio error");
      } else {
        debugPrint(e.toString());
      }
    }
  }
}
