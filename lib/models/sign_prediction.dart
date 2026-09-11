class SignPrediction {
  const SignPrediction({
    required this.label,
    required this.confidence,
    required this.scores,
  });

  final String label;
  final double confidence;
  final List<double> scores;

  String get confidenceText => '${(confidence * 100).toStringAsFixed(1)}%';
}

class ImagePredictionResult {
  const ImagePredictionResult({
    required this.path,
    this.prediction,
    this.error,
  });

  final String path;
  final SignPrediction? prediction;
  final String? error;
}
