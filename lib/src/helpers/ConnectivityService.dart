import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flyweb/src/enum/connectivity_status.dart';

class ConnectivityService {
  StreamController<ConnectivityStatus> connectionStatusController =
  StreamController<ConnectivityStatus>();

  ConnectivityService() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      var connectionsStatus = _getStatusFromResult(result[0]);
      connectionStatusController.add(connectionsStatus);
    });
  }

  ConnectivityStatus _getStatusFromResult(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.mobile:
        return ConnectivityStatus.Cellular;
      case ConnectivityResult.wifi:
        return ConnectivityStatus.Wifi;
      case ConnectivityResult.none:
        return ConnectivityStatus.Offline;
      default:
        return ConnectivityStatus.Offline;
    }
  }
}
