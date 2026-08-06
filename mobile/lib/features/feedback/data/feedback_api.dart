import 'package:dio/dio.dart';

/// `POST /api/feedback` (`backend/src/routes/feedback.routes.js:24-70`).
class FeedbackApi {
  FeedbackApi(this._dio);

  final Dio _dio;

  Future<void> submit({
    required int overallRating,
    required Map<String, int> categoryRatings,
    String? comment,
    bool? wouldRecommend,
  }) async {
    await _dio.post(
      '/feedback',
      data: {
        'overallRating': overallRating,
        'categoryRatings': categoryRatings,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        if (wouldRecommend != null) 'wouldRecommend': wouldRecommend ? 'yes' : 'no',
      },
    );
  }
}
