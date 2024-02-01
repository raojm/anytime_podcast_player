// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:anytime/core/environment.dart';
import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/services/download/download_manager.dart';
// import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:logging/logging.dart';

/// A [DownloadManager] for handling downloading of podcasts on a mobile device.
class MobileDownloaderManager implements DownloadManager {
  static const portName = 'downloader_send_port';
  final log = Logger('MobileDownloaderManager');
  final ReceivePort _port = ReceivePort();
  final downloadController = StreamController<DownloadProgress>();
  var _lastUpdateTime = 0;

  @override
  Stream<DownloadProgress> get downloadProgress => downloadController.stream;

  MobileDownloaderManager() {
    _init();
  }

  Future _init() async {
    log.fine('Initialising download manager');


    FileDownloader()
        .configure(
        globalConfig: [
          (Config.requestTimeout, const Duration(seconds: 100)),
        ],
        androidConfig: [
          (Config.useCacheDir, Config.whenAble),
        ],
        iOSConfig: [
          (Config.localize, {'Cancel': 'StopIt'}),
        ])
        .then((result) => log.fine('Configuration result = $result'));

    // Registering a callback and configure notifications
    FileDownloader()
        .registerCallbacks(taskNotificationTapCallback: myNotificationTapCallback)
        .configureNotificationForGroup(FileDownloader.defaultGroup,
        // For the main download button
        // which uses 'enqueue' and a default group
        running: const TaskNotification('Download {filename}',
            'File: {filename} - {progress} - speed {networkSpeed} and {timeRemaining} remaining'),
        complete: const TaskNotification(
            '{displayName} download {filename}', 'Download complete'),
        error: const TaskNotification(
            'Download {filename}', 'Download failed'),
        paused: const TaskNotification(
            'Download {filename}', 'Paused with metadata {metadata}'),
        progressBar: true)
        .configureNotificationForGroup('bunch',
        running: const TaskNotification(
            '{numFinished} out of {numTotal}', 'Progress = {progress}'),
        complete:
        const TaskNotification("Done!", "Loaded {numTotal} files"),
        error: const TaskNotification(
            'Error', '{numFailed}/{numTotal} failed'),
        progressBar: false,
        groupNotificationId: 'notGroup')
        .configureNotification(
      // for the 'Download & Open' dog picture
      // which uses 'download' which is not the .defaultGroup
      // but the .await group so won't use the above config
        complete: const TaskNotification(
            'Download {filename}', 'Download complete'),
        tapOpensFile: true); // dog can also open directly from tap

    // Listen to updates and process
    FileDownloader().updates.listen((update) {
      switch (update) {
        case TaskStatusUpdate _:
          if(update.status == TaskStatus.enqueued)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 0, DownloadState.queued));
          }
          else if(update.status == TaskStatus.failed)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 0, DownloadState.failed));
          }
          else if(update.status == TaskStatus.canceled)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 0, DownloadState.cancelled));
          }
          else if(update.status == TaskStatus.notFound)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 0, DownloadState.failed));
          }
          else if(update.status == TaskStatus.paused)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 30, DownloadState.paused));
          }
          else if(update.status == TaskStatus.complete)
          {
            downloadController.add(DownloadProgress(update.task.taskId, 100, DownloadState.downloaded));
          }
          else if(update.status == TaskStatus.waitingToRetry)
          {
            // downloadController.add(DownloadProgress(update.task.taskId, 0, DownloadState.failed));
          }
      // if (update.task == backgroundDownloadTask) {
      //   buttonState = switch (update.status) {
      //     TaskStatus.running || TaskStatus.enqueued => ButtonState.pause,
      //     TaskStatus.paused => ButtonState.resume,
      //     _ => ButtonState.reset
      //   };
      //   setState(() {
      //     downloadTaskStatus = update.status;
      //   });
      // }

        case TaskProgressUpdate _:
        // progressUpdateStream.add(update); // pass on to widget for indicator
          downloadController.add(DownloadProgress(update.task.taskId, (100*update.progress).toInt(), DownloadState.downloading));
      }
    });

    // await FlutterDownloader.initialize();
    IsolateNameServer.removePortNameMapping(portName);

    IsolateNameServer.registerPortWithName(_port.sendPort, portName);

    // var tasks = await FlutterDownloader.loadTasks();
    //
    // // Update the status of any tasks that may have been updated whilst
    // // AnyTime was close or in the background.
    // if (tasks != null && tasks.isNotEmpty) {
    //   for (var t in tasks) {
    //     _updateDownloadState(id: t.taskId, progress: t.progress, status: t.status.index);
    //
    //     /// If we are not queued or running we can safely clean up this event
    //     if (t.status != DownloadTaskStatus.enqueued && t.status != DownloadTaskStatus.running) {
    //       FlutterDownloader.remove(taskId: t.taskId, shouldDeleteContent: false);
    //     }
    //   }
    // }

    _port.listen((dynamic data) {
      final id = data[0] as String;
      final status = data[1] as int;
      final progress = data[2] as int;

      // _updateDownloadState(id: id, progress: progress, status: status);
    });

    // FlutterDownloader.registerCallback(downloadCallback);
  }

  @override
  Future<String?> enqueueTask(String url, String downloadPath, String fileName) async {
    // return await FlutterDownloader.enqueue(
    //   url: url,
    //   savedDir: downloadPath,
    //   fileName: fileName,
    //   showNotification: true,
    //   openFileFromNotification: false,
    //   headers: {
    //     'User-Agent': Environment.userAgent(),
    //   },
    // );
    final task = DownloadTask(
        url: url,
        filename: fileName,
        directory: downloadPath,
        baseDirectory: BaseDirectory.root,
        updates: Updates.statusAndProgress);

    final successfullyEnqueued = await FileDownloader().enqueue(task);
    return task.taskId;
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping(portName);
    downloadController.close();
  }

  void _updateDownloadState({required String id, required int progress, required int status}) {
    log.fine('_updateDownloadState');
    //   var state = DownloadState.none;
    //   var updateTime = DateTime.now().millisecondsSinceEpoch;
    //   var downloadStatus = DownloadTaskStatus.fromInt(status);
    //
    //   if (downloadStatus == DownloadTaskStatus.enqueued) {
    //     state = DownloadState.queued;
    //   } else if (downloadStatus == DownloadTaskStatus.canceled) {
    //     state = DownloadState.cancelled;
    //   } else if (downloadStatus == DownloadTaskStatus.complete) {
    //     state = DownloadState.downloaded;
    //   } else if (downloadStatus == DownloadTaskStatus.running) {
    //     state = DownloadState.downloading;
    //   } else if (downloadStatus == DownloadTaskStatus.failed) {
    //     state = DownloadState.failed;
    //   } else if (downloadStatus == DownloadTaskStatus.paused) {
    //     state = DownloadState.paused;
    //   }
    //
    //   /// If we are running, we want to limit notifications to 1 per second. Otherwise,
    //   /// small downloads can cause a flood of events. Any other status we always want
    //   /// to push through.
    //   if (downloadStatus != DownloadTaskStatus.running ||
    //       progress == 0 ||
    //       progress == 100 ||
    //       updateTime > _lastUpdateTime + 1000) {
    //     downloadController.add(DownloadProgress(id, progress, state));
    //     _lastUpdateTime = updateTime;
    //   }
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    IsolateNameServer.lookupPortByName('downloader_send_port')?.send([id, status, progress]);
  }

  /// Process the user tapping on a notification by printing a message
  void myNotificationTapCallback(Task task, NotificationType notificationType) {
    log.fine(
        'Tapped notification $notificationType for taskId ${task.taskId}');
    if (NotificationType.complete == notificationType) {
      IsolateNameServer.lookupPortByName('downloader_send_port')?.send(
          [task.taskId, DownloadState.downloaded, 100]);
    }
  }

}
