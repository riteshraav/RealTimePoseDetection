import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:pose_detection_realtime/Model/ExerciseDataModel.dart';

import 'Model/Exercise.dart';
import 'main.dart';

class DetectionScreen extends StatefulWidget {
  DetectionScreen({Key? key, required this.exerciseDataModel})
      : super(key: key);
  ExerciseDataModel exerciseDataModel;
  @override
  _DetectionScreenState createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  dynamic controller;
  bool isBusy = false;
  late Size size;
  late List<Exercise> squatPoseList;
  int repCount = 0;
  int repPhase = 0; // 0=initial, 1=mid, 2=endX

  final List<String> repSequence = ["initial", "mid", "end"];
  //TODO declare detector
  late PoseDetector poseDetector;
  @override
  void initState() {
    super.initState();
    initializeCamera();
    loadSquatData();
  }
  //[1.039965378768594, 0.9604117817391636, 0.913183064334068, 1.0802637332588652, 1.310695646118117]
  void loadSquatData(){
    final String squatJsonString = '''
   [{
    "label":"squat",
    "position":"start",
    "vector":[1.0758621466227754, 0.9628157029330505, 0.8972414765179114, 1.0729556322352511, 1.1767835206372965]
},
{
    "label":"squat",
    "position":"mid",
    "vector":[1.2352999678242411, 0.7708923811313935, 0.7738196239980013, 1.2272868329478852, 1.4352094816629295]
},

{
    "label":"squat",
    "position":"end",
    "vector": [1.633372904882686, 0.3471283218545209, 0.42263478797982873, 1.5608754750990699, 1.0764200252215734]
}
]  ''';
    List<dynamic> decodedSquatData = jsonDecode(squatJsonString);
    squatPoseList = decodedSquatData.map((e) => Exercise.fromJson(e)).toList();
  }

  //TODO code to initialize the camera feed
  initializeCamera() async {
    //TODO initialize detector
    final options = PoseDetectorOptions(mode: PoseDetectionMode.stream);
    poseDetector = PoseDetector(options: options);

    controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup:
      Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      controller.startImageStream(
            (image) => {
          if (!isBusy) {isBusy = true, img = image, doPoseEstimationOnFrame()},
        },
      );
    });
  }

  //TODO pose detection on a frame
  dynamic _scanResults;
  CameraImage? img;
  doPoseEstimationOnFrame() async {
    var inputImage = _inputImageFromCameraImage();
    if (inputImage != null) { print("input image is detected"); }
    if (inputImage != null) {
      final List<Pose> poses = await poseDetector.processImage(inputImage!);
      _scanResults = poses;
      if (poses.length > 0) {
        if (widget.exerciseDataModel.type == ExerciseType.PushUps) {
          detectPushUp(poses.first.landmarks);
        } else if (widget.exerciseDataModel.type == ExerciseType.Squats) {
          processPoseVector(poses.first);
        } else if (widget.exerciseDataModel.type ==
            ExerciseType.DownwardDogPlank) {
          detectPlankToDownwardDog(poses.first);
        } else if (widget.exerciseDataModel.type == ExerciseType.JumpingJack) {
          detectJumpingJack(poses.first);
        }
      }
    }
    setState(() {
      _scanResults;
      isBusy = false;
    });
  }

  //close all resources
  @override
  void dispose() {
    controller?.dispose();
    poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> stackChildren = [];
    size = MediaQuery.of(context).size;
    if (controller != null) {
      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: Container(
            child:
            (controller.value.isInitialized)
                ? AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            )
                : Container(),
          ),
        ),
      );

      stackChildren.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: buildResult(),
        ),
      );
      stackChildren.add(
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              color: Colors.black,
            ),
            child: Center(
              child: Text(
                widget.exerciseDataModel.type == ExerciseType.PushUps
                    ? "$pushUpCount"
                    : widget.exerciseDataModel.type == ExerciseType.Squats
                    ? "$squatCount"
                    : widget.exerciseDataModel.type ==
                    ExerciseType.DownwardDogPlank
                    ? "$plankToDownwardDogCount"
                    : "$jumpingJackCount",
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            width: 70,
            height: 70,
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        margin: const EdgeInsets.only(top: 0),
        color: Colors.black,
        child: Stack(children: stackChildren),
      ),
    );
  }

  int pushUpCount = 0;
  bool isLowered = false;
  void detectPushUp(Map<PoseLandmarkType, PoseLandmark> landmarks) {
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftWrist == null ||
        rightWrist == null ||
        leftHip == null ||
        rightHip == null) {
      return; // Skip if any landmark is missing
    }

    // Calculate elbow angles
    double leftElbowAngle = calculateAngle(leftShoulder, leftElbow, leftWrist);
    double rightElbowAngle = calculateAngle(
      rightShoulder,
      rightElbow,
      rightWrist,
    );
    double avgElbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    // Calculate torso alignment (ensuring a straight plank)
    double torsoAngle = calculateAngle(
      leftShoulder,
      leftHip,
      leftKnee ?? rightKnee!,
    );
    bool inPlankPosition =
        torsoAngle > 160 && torsoAngle < 180; // Slight flexibility

    if (avgElbowAngle < 90 && inPlankPosition) {
      // User is in the lowered push-up position
      isLowered = true;
    } else if (avgElbowAngle > 160 && isLowered && inPlankPosition) {
      // User returns to the starting position
      pushUpCount++;
      isLowered = false;

      // Update UI
      setState(() {});
    }
  }

  int squatCount = 0;
  bool isSquatting = false;
  void detectSquat(Map<PoseLandmarkType, PoseLandmark> landmarks) {
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];

    if (leftHip == null ||
        rightHip == null ||
        leftKnee == null ||
        rightKnee == null ||
        leftAnkle == null ||
        rightAnkle == null ||
        leftShoulder == null ||
        rightShoulder == null) {
      return; // Skip detection if any key landmark is missing
    }

    // Calculate angles
    double leftKneeAngle = calculateAngle(leftHip, leftKnee, leftAnkle);
    double rightKneeAngle = calculateAngle(rightHip, rightKnee, rightAnkle);
    double avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    double hipY = (leftHip.y + rightHip.y) / 2;
    double kneeY = (leftKnee.y + rightKnee.y) / 2;

    bool deepSquat = avgKneeAngle < 90; // Ensuring squat is deep enough

    if (deepSquat && hipY > kneeY) {
      if (!isSquatting) {
        isSquatting = true;
      }
    } else if (!deepSquat && isSquatting) {
      squatCount++;
      isSquatting = false;

      // Update UI
      setState(() {});
    }
  }
  /// Cosine similarity
  double cosineSimilarity(List<double> v1, List<double> v2) {
    double dot = 0, mag1 = 0, mag2 = 0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
      mag1 += v1[i] * v1[i];
      mag2 += v2[i] * v2[i];
    }
    return dot / (sqrt(mag1) * sqrt(mag2));
  }
  /// Euclidean distance between two vectors
  double euclideanDistance(List<double> v1, List<double> v2) {
    double sum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      double diff = v1[i] - v2[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// Process live pose vector for rep detection
  void processPoseVector(Pose pose) {
    print('processPoseVector called');

    // Step 1: Extract current pose vector
    List<double>? currentVector = getPoseVector(pose);
    if (currentVector == null) {
      print("current vector is null");
      return;
    }

    // Step 2: Filter ideal vectors for squat only ("start" or "endX")
    final idealVectors = squatPoseList
        .where((e) => e.label == 'squat' && (e.position == "start" || e.position == "mid" || e.position.startsWith("end")))
        .toList();

    if (idealVectors.isEmpty) {
      print('ideal vectors are empty');
      return;
    }

    // Step 3: Find best matching reference vector
    Exercise? bestMatch;
    double bestSim = -1.0;

    for (var ref in idealVectors) {
      double sim = cosineSimilarity(currentVector, ref.vector);
      print('Cosine similarity with ${ref.position} = $sim');
      if (sim > bestSim) {
        bestSim = sim;
        bestMatch = ref;
      }
    }

    if (bestMatch == null) {
      print('No good match found');
      return;
    }

    String matched = bestMatch.position;
    print('Matched position: $matched');

    // Step 4: Three-phase state machine: start → mid → end → start
    if (repPhase == 0 && matched == "start") {
      // Stay in start phase
      print("In start position, waiting to move...");
    } else if (repPhase == 0 && matched == "mid") {
      // Transition to mid phase
      repPhase = 1;
      print("Mid position reached");
    } else if (repPhase == 1 && matched.startsWith("end")) {
      // Transition to end phase
      repPhase = 2;
      print("End position reached");
    } else if (repPhase == 2 && matched == "start") {
      // Rep completed, return to start
      repCount++;
      squatCount++;
      repPhase = 0;
      setState(() {}); // Update UI
      print(" Squat rep completed. Total reps: $repCount");
      print("Squat rep completed. Total squat: $squatCount");
    } else {
      print("Unrecognized or invalid phase transition");
    }
    print('Current phase: $repPhase');
  }


  List<double>? getPoseVector(Pose pose) {
    if (pose.landmarks.isEmpty) return null;

    final lm = pose.landmarks;
    List<double> vector = [];

    // Helper function to get landmark or null
    PoseLandmark? get(PoseLandmarkType type) => lm.containsKey(type) ? lm[type] : null;

    // --- ANGLES ---
    double? leftKneeAngle = _angle(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftKnee), get(PoseLandmarkType.leftAnkle));
    double? rightKneeAngle = _angle(get(PoseLandmarkType.rightHip), get(PoseLandmarkType.rightKnee), get(PoseLandmarkType.rightAnkle));

    double? leftHipAngle = _angle(get(PoseLandmarkType.leftShoulder), get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftKnee));
    double? rightHipAngle = _angle(get(PoseLandmarkType.rightShoulder), get(PoseLandmarkType.rightHip), get(PoseLandmarkType.rightKnee));

    // --- DISTANCES ---
    double? hipHeight = _yDist(get(PoseLandmarkType.leftHip), get(PoseLandmarkType.leftAnkle));
    double? torsoLength = _yDist(get(PoseLandmarkType.leftShoulder), get(PoseLandmarkType.leftHip));

    // Add normalized or zero-safe values
    vector.addAll([
      (leftKneeAngle ?? 0.0) / 180.0,
      (rightKneeAngle ?? 0.0) / 180.0,
      (leftHipAngle ?? 0.0) / 180.0,
      (rightHipAngle ?? 0.0) / 180.0,
      (hipHeight ?? 0.0) / (torsoLength != null && torsoLength > 0 ? torsoLength : 1.0),
    ]);
    print(vector);
    return vector;
  }

  double? _angle(PoseLandmark? a, PoseLandmark? b, PoseLandmark? c) {
    if (a == null || b == null || c == null) return null;
    final radians = atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
    double angle = radians * 180 / pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  double? _yDist(PoseLandmark? a, PoseLandmark? b) {
    if (a == null || b == null) return null;
    return (a.y - b.y).abs();
  }

  int plankToDownwardDogCount = 0;
  bool isInDownwardDog = false;
  void detectPlankToDownwardDog(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    if (leftHip == null ||
        rightHip == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftAnkle == null ||
        rightAnkle == null ||
        leftWrist == null ||
        rightWrist == null) {
      return; // Skip detection if any key landmark is missing
    }

    // **Step 1: Detect Plank Position**
    bool isPlank =
        (leftHip.y - leftShoulder.y).abs() < 30 &&
            (rightHip.y - rightShoulder.y).abs() < 30 &&
            (leftHip.y - leftAnkle.y).abs() > 100 &&
            (rightHip.y - rightAnkle.y).abs() > 100;

    // **Step 2: Detect Downward Dog Position**
    bool isDownwardDog =
        (leftHip.y < leftShoulder.y - 50) &&
            (rightHip.y < rightShoulder.y - 50) &&
            (leftAnkle.y > leftHip.y) &&
            (rightAnkle.y > rightHip.y);

    // **Step 3: Count Repetitions**
    if (isDownwardDog && !isInDownwardDog) {
      isInDownwardDog = true;
    } else if (isPlank && isInDownwardDog) {
      plankToDownwardDogCount++;
      isInDownwardDog = false;

      // Print count
      print("Plank to Downward Dog Count: $plankToDownwardDogCount");
    }
  }

  int jumpingJackCount = 0;
  bool isJumping = false;
  bool isJumpingJackOpen = false;
  void detectJumpingJack(Pose pose) {
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    if (leftAnkle == null ||
        rightAnkle == null ||
        leftHip == null ||
        rightHip == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftWrist == null ||
        rightWrist == null) {
      return; // Skip detection if any landmark is missing
    }

    // Calculate distances
    double legSpread = (rightAnkle.x - leftAnkle.x).abs();
    double armHeight = (leftWrist.y + rightWrist.y) / 2; // Average wrist height
    double hipHeight = (leftHip.y + rightHip.y) / 2; // Average hip height
    double shoulderWidth = (rightShoulder.x - leftShoulder.x).abs();

    // Define thresholds based on shoulder width
    double legThreshold =
        shoulderWidth * 1.2; // Legs should be ~1.2x shoulder width apart
    double armThreshold =
        hipHeight - shoulderWidth * 0.5; // Arms should be above shoulders

    // Check if arms are raised and legs are spread
    bool armsUp = armHeight < armThreshold;
    bool legsApart = legSpread > legThreshold;

    // Detect full jumping jack cycle
    if (armsUp && legsApart && !isJumpingJackOpen) {
      isJumpingJackOpen = true;
    } else if (!armsUp && !legsApart && isJumpingJackOpen) {
      jumpingJackCount++;
      isJumpingJackOpen = false;

      // Print the count
      print("Jumping Jack Count: $jumpingJackCount");
    }
  }

  // Function to calculate angle between three points (shoulder, elbow, wrist)
  double calculateAngle(
      PoseLandmark shoulder,
      PoseLandmark elbow,
      PoseLandmark wrist,
      ) {
    double a = distance(elbow, wrist);
    double b = distance(shoulder, elbow);
    double c = distance(shoulder, wrist);

    double angle = acos((b * b + a * a - c * c) / (2 * b * a)) * (180 / pi);
    return angle;
  }

  // Helper function to calculate Euclidean distance
  double distance(PoseLandmark p1, PoseLandmark p2) {
    return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2));
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  InputImage? _inputImageFromCameraImage() {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas
    final camera = cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
      _orientations[controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;
    // get image format
    final format = InputImageFormatValue.fromRawValue(img!.format.raw);

    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      if (Platform.isAndroid && format == InputImageFormat.yuv_420_888) {
        return convertYUV420ToInputImage(img, rotation);
      }
    }

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (img!.planes.length != 1) return null;
    final plane = img!.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(img!.width.toDouble(), img!.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format!, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }

  InputImage? convertYUV420ToInputImage(CameraImage? img, InputImageRotation rotation) {
    if (Platform.isAndroid && img!.format.group != ImageFormatGroup.yuv420) return null;

    final width = img!.width;
    final height = img.height;

    final yPlane = img.planes[0];
    final uPlane = img.planes[1];
    final vPlane = img.planes[2];

    final ySize = yPlane.bytes.length;
    final uvSize = width * height ~/ 2;
    final nv21Bytes = Uint8List(ySize + uvSize);

    // Copy Y
    nv21Bytes.setRange(0, ySize, yPlane.bytes);

    // Interleave V and U (NV21 expects V first, then U)
    int offset = ySize;
    final pixelStride = uPlane.bytesPerPixel ?? 2; // typically 2
    final rowStride = uPlane.bytesPerRow;

    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final uvIndex = row * rowStride + col * pixelStride;
        nv21Bytes[offset++] = vPlane.bytes[uvIndex]; // V
        nv21Bytes[offset++] = uPlane.bytes[uvIndex]; // U
      }
    }

    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21, // must match the bytes layout
        bytesPerRow: width, // optional on Android
      ),
    );
  }

  //Show rectangles around detected objects
  Widget buildResult() {
    if (_scanResults == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Text('');
    }
    final Size imageSize = Size(
      controller.value.previewSize!.height,
      controller.value.previewSize!.width,
    );
    CustomPainter painter = PosePainter(imageSize, _scanResults);
    return CustomPaint(painter: painter);
  }
}