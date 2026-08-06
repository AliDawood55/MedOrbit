import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/feedback_api.dart';

enum FeedbackSubmitStatus { idle, submitting, success, error }

class FeedbackFormState {
  const FeedbackFormState({
    this.overallRating = 0,
    this.chatbotRating = 0,
    this.clinicsRating = 0,
    this.bookingRating = 0,
    this.designRating = 0,
    this.comment = '',
    this.wouldRecommend,
    this.status = FeedbackSubmitStatus.idle,
    this.showRatingRequiredError = false,
  });

  final int overallRating;
  final int chatbotRating;
  final int clinicsRating;
  final int bookingRating;
  final int designRating;
  final String comment;
  final bool? wouldRecommend;
  final FeedbackSubmitStatus status;
  final bool showRatingRequiredError;

  FeedbackFormState copyWith({
    int? overallRating,
    int? chatbotRating,
    int? clinicsRating,
    int? bookingRating,
    int? designRating,
    String? comment,
    bool? clearRecommend,
    bool? wouldRecommend,
    FeedbackSubmitStatus? status,
    bool? showRatingRequiredError,
  }) {
    return FeedbackFormState(
      overallRating: overallRating ?? this.overallRating,
      chatbotRating: chatbotRating ?? this.chatbotRating,
      clinicsRating: clinicsRating ?? this.clinicsRating,
      bookingRating: bookingRating ?? this.bookingRating,
      designRating: designRating ?? this.designRating,
      comment: comment ?? this.comment,
      wouldRecommend: (clearRecommend ?? false) ? null : (wouldRecommend ?? this.wouldRecommend),
      status: status ?? this.status,
      showRatingRequiredError: showRatingRequiredError ?? false,
    );
  }
}

final feedbackApiProvider = Provider<FeedbackApi>((ref) => FeedbackApi(ref.watch(dioProvider)));

class FeedbackController extends StateNotifier<FeedbackFormState> {
  FeedbackController(this._api) : super(const FeedbackFormState());

  final FeedbackApi _api;

  void setOverallRating(int value) => state = state.copyWith(overallRating: value, showRatingRequiredError: false);
  void setChatbotRating(int value) => state = state.copyWith(chatbotRating: value);
  void setClinicsRating(int value) => state = state.copyWith(clinicsRating: value);
  void setBookingRating(int value) => state = state.copyWith(bookingRating: value);
  void setDesignRating(int value) => state = state.copyWith(designRating: value);
  void setComment(String value) => state = state.copyWith(comment: value);

  /// Tapping the already-selected option deselects it (mirrors
  /// `feedback.js:44-60`'s click-again-to-clear behavior).
  void setRecommend(bool value) {
    if (state.wouldRecommend == value) {
      state = state.copyWith(clearRecommend: true);
    } else {
      state = state.copyWith(wouldRecommend: value);
    }
  }

  Future<void> submit() async {
    if (state.overallRating < 1) {
      state = state.copyWith(showRatingRequiredError: true);
      return;
    }
    state = state.copyWith(status: FeedbackSubmitStatus.submitting);
    try {
      await _api.submit(
        overallRating: state.overallRating,
        categoryRatings: {
          'chatbot': state.chatbotRating,
          'clinics': state.clinicsRating,
          'booking': state.bookingRating,
          'design': state.designRating,
        },
        comment: state.comment.trim().isEmpty ? null : state.comment.trim(),
        wouldRecommend: state.wouldRecommend,
      );
      state = state.copyWith(status: FeedbackSubmitStatus.success);
    } catch (_) {
      state = state.copyWith(status: FeedbackSubmitStatus.error);
    }
  }

  void reset() => state = const FeedbackFormState();
}

final feedbackControllerProvider = StateNotifierProvider.autoDispose<FeedbackController, FeedbackFormState>(
  (ref) => FeedbackController(ref.watch(feedbackApiProvider)),
);
