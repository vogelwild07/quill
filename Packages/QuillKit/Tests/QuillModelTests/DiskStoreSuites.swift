import Testing

/// Suiten mit Stores samt Bildern auf der Platte laufen nacheinander, nicht parallel
/// zueinander: Mehrere `ModelContainer` im selben Prozess vermischten sonst externe
/// Bilddaten verschiedener Stores (eine Suite las die Bildbytes einer anderen). In der
/// App gibt es nur einen Container pro Prozess.
@Suite(.serialized) enum DiskStoreSuites {}
