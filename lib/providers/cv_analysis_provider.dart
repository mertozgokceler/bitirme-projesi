import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/cv/cv_repository.dart';

class CvAnalysisProvider extends ChangeNotifier {
  final CvRepository _repo;
  final FirebaseAuth _auth;

  CvAnalysisProvider({
    CvRepository? repo,
    FirebaseAuth? auth,
  })  : _repo = repo ?? CvRepository(),
        _auth = auth ?? FirebaseAuth.instance;

  // ---------- UI state ----------
  bool loading = true;
  bool busy = false;

  // ---------- CV state ----------
  CvInfo? cv;

  // ---------- Analysis state ----------
  bool analyzing = false;
  String? analysisId;
  Map<String, dynamic>? analysisDoc;
  DateTime? analysisUpdatedAt;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _analysisSub;

  // ---------- History state ----------
  bool historyExpanded = false;
  bool historyLoading = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> historyDocs = [];
  String? historyError;

  // ---------- Credits state ----------
  bool creditsLoading = false;
  bool isPremium = false;
  int dailyLimit = 3; // free default
  int usedToday = 0;

  int get remainingToday => (dailyLimit - usedToday).clamp(0, dailyLimit);

  String get _uid => _auth.currentUser!.uid;
  bool get isLoggedIn => _auth.currentUser != null;
  bool get hasCv => cv != null && cv!.hasCv;

  // ---------------------------
  // Lifecycle
  // ---------------------------
  @override
  void dispose() {
    _analysisSub?.cancel();
    super.dispose();
  }

  // ---------------------------
  // Bootstrap
  // ---------------------------
  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();

    if (!isLoggedIn) {
      _clearAll();
      loading = false;
      notifyListeners();
      return;
    }

    try {
      cv = await _repo.resolveCvFromFirestoreOrStorage(_uid);

      final latest = await _repo.loadLatestAnalysis(_uid);
      if (latest != null) {
        analysisId = latest.id;
        analysisDoc = latest.data;
        analysisUpdatedAt = _pickBestTime(latest.data);
        analyzing = _isQueuedOrRunning(latest.data['status']);
        _startAnalysisListener(latest.id);
      } else {
        _stopAnalysisListener();
        analysisId = null;
        analysisDoc = null;
        analysisUpdatedAt = null;
        analyzing = false;
      }

      await refreshCredits();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---------------------------
  // Credits
  // ---------------------------
  Future<void> refreshCredits() async {
    if (!isLoggedIn) return;

    creditsLoading = true;
    notifyListeners();

    try {
      isPremium = await _repo.isPremiumActive(_uid);
      dailyLimit = isPremium ? 15 : 3;
      usedToday = await _repo.countTodayAnalyses(_uid);
    } finally {
      creditsLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------
  // CV actions
  // ---------------------------
  Future<void> uploadCvPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!isLoggedIn) throw Exception('Önce giriş yapmalısın.');

    busy = true;
    notifyListeners();

    try {
      cv = await _repo.uploadCvPdf(
        uid: _uid,
        bytes: bytes,
        originalFileName: fileName,
      );

      // CV değişti -> eski analiz "stale"
      _stopAnalysisListener();
      analysisId = null;
      analysisDoc = null;
      analysisUpdatedAt = null;
      analyzing = false;

      // history açık ise yenile
      if (historyExpanded) {
        await fetchHistory(force: true);
      }

      await refreshCredits();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteCv() async {
    if (!isLoggedIn) throw Exception('Önce giriş yapmalısın.');

    busy = true;
    notifyListeners();

    try {
      await _repo.deleteCv(uid: _uid, storagePathFromState: cv?.storagePath);

      cv = null;

      _stopAnalysisListener();
      analysisId = null;
      analysisDoc = null;
      analysisUpdatedAt = null;
      analyzing = false;

      historyDocs = [];
      historyError = null;
      historyExpanded = false;
      historyLoading = false;

      await refreshCredits();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------------------------
  // Analysis actions
  // ---------------------------
  Future<void> runAnalysis() async {
    if (!isLoggedIn) throw Exception('Önce giriş yapmalısın.');
    if (!hasCv) throw Exception('Önce CV yüklemelisin.');

    // Limit kontrolü (GERÇEK)
    await refreshCredits();
    if (remainingToday <= 0) {
      throw Exception(isPremium
          ? 'Günlük CV analiz hakkın bitti (15/15). Yarın tekrar dene.'
          : 'Günlük CV analiz hakkın bitti (3/3). Premium ile günlük 15 hak alırsın.');
    }

    analyzing = true;
    analysisDoc = null;
    analysisUpdatedAt = null;
    notifyListeners();

    try {
      final id = await _repo.createAnalysis(
        uid: _uid,
        cvUrl: cv!.url,
        targetRole: null,
      );

      analysisId = id;
      _startAnalysisListener(id);

      if (historyExpanded) {
        await fetchHistory(force: true);
      }

      // Analiz kaydı oluştu -> bugün kullanım arttı
      await refreshCredits();
    } catch (_) {
      analyzing = false;
      notifyListeners();
      rethrow;
    }
  }

  void openHistoryItem(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final id = doc.id;
    final data = doc.data();

    _stopAnalysisListener();

    analysisId = id;
    analysisDoc = data;
    analysisUpdatedAt = _pickBestTime(data);
    analyzing = _isQueuedOrRunning(data['status']);

    notifyListeners();

    _startAnalysisListener(id);
  }

  // ---------------------------
  // History
  // ---------------------------
  Future<void> toggleHistory() async {
    historyExpanded = !historyExpanded;
    historyError = null;
    notifyListeners();

    if (historyExpanded) {
      await fetchHistory(force: true);
    }
  }

  Future<void> fetchHistory({bool force = false}) async {
    if (!isLoggedIn) return;
    if (!force && historyDocs.isNotEmpty) return;

    historyLoading = true;
    historyError = null;
    notifyListeners();

    try {
      historyDocs = await _repo.fetchHistory(uid: _uid, limit: 25);
    } catch (e) {
      historyError = 'Geçmiş analizler alınamadı: $e';
    } finally {
      historyLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------
  // Listener
  // ---------------------------
  void _startAnalysisListener(String id) {
    _analysisSub?.cancel();
    _analysisSub = _repo.watchAnalysis(id).listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      analysisId = id;
      analysisDoc = data;
      analysisUpdatedAt = _pickBestTime(data);
      analyzing = _isQueuedOrRunning(data['status']);

      notifyListeners();
    }, onError: (e) {
      // hata yutma yok
      analysisDoc ??= {};
      analysisDoc = Map<String, dynamic>.from(analysisDoc!);
      analysisDoc!['status'] = 'error';
      analysisDoc!['error'] = 'Analiz dinleme hatası: $e';
      analyzing = false;
      notifyListeners();
    });
  }

  void _stopAnalysisListener() {
    _analysisSub?.cancel();
    _analysisSub = null;
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  bool _isQueuedOrRunning(dynamic rawStatus) {
    final s = (rawStatus ?? '').toString().trim().toLowerCase();
    return s == 'queued' || s == 'running';
  }

  DateTime? _pickBestTime(Map<String, dynamic>? data) {
    if (data == null) return null;

    DateTime? toDt(dynamic x) => x is Timestamp ? x.toDate() : null;

    return toDt(data['finishedAt']) ??
        toDt(data['startedAt']) ??
        toDt(data['createdAt']);
  }

  void _clearAll() {
    cv = null;

    _stopAnalysisListener();
    analyzing = false;
    analysisId = null;
    analysisDoc = null;
    analysisUpdatedAt = null;

    historyExpanded = false;
    historyLoading = false;
    historyDocs = [];
    historyError = null;

    creditsLoading = false;
    isPremium = false;
    dailyLimit = 3;
    usedToday = 0;
  }
}
