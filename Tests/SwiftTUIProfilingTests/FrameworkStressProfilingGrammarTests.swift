import Testing

@testable import SwiftTUIProfiling

@Suite("SwiftTUI profiling grammar stress behavior", .serialized)
struct FrameworkStressProfilingGrammarTests {
  @Test("stress profiling grammar 001 duplicate frame signals collapse")
  func profilingGrammar001DuplicateFrameSignalsCollapse() {
    #expect(EnvProfileParser.parse("frames,frames")?.signals == [.frames])
  }

  @Test("stress profiling grammar 002 duplicate memory intervals collapse")
  func profilingGrammar002DuplicateMemoryIntervalsCollapse() {
    #expect(
      EnvProfileParser.parse("memory@5ms,memory@5ms")?.signals == [
        .memory(interval: .milliseconds(5))
      ])
  }

  @Test("stress profiling grammar 003 distinct memory intervals remain distinct")
  func profilingGrammar003DistinctMemoryIntervalsRemainDistinct() {
    #expect(EnvProfileParser.parse("memory@5ms,memory@6ms")?.signals.count == 2)
  }

  @Test("stress profiling grammar 004 distinct CPU intervals remain distinct")
  func profilingGrammar004DistinctCPUIntervalsRemainDistinct() {
    #expect(EnvProfileParser.parse("cpu@1s,cpu@2s")?.signals.count == 2)
  }

  @Test("stress profiling grammar 005 signal order does not change the signal set")
  func profilingGrammar005SignalOrderDoesNotChangeSignalSet() {
    #expect(
      EnvProfileParser.parse("cpu,frames,memory")?.signals
        == EnvProfileParser.parse("memory,cpu,frames")?.signals)
  }

  @Test("stress profiling grammar 006 sink order remains authored")
  func profilingGrammar006SinkOrderRemainsAuthored() {
    #expect(
      EnvProfileParser.parse("frames;summary,tsv=/a,jsonl=/b")?.sinks == [
        .summary, .tsv(path: "/a"), .jsonl(path: "/b"),
      ])
  }

  @Test("stress profiling grammar 007 duplicate sinks remain independently authored")
  func profilingGrammar007DuplicateSinksRemainIndependentlyAuthored() {
    #expect(EnvProfileParser.parse("frames;summary,summary")?.sinks == [.summary, .summary])
  }

  @Test("stress profiling grammar 008 sink paths preserve additional equals signs")
  func profilingGrammar008SinkPathsPreserveAdditionalEqualsSigns() {
    #expect(
      EnvProfileParser.parse("frames;tsv=/tmp/a=b.tsv")?.sinks == [.tsv(path: "/tmp/a=b.tsv")])
  }

  @Test("stress profiling grammar 009 sink paths preserve internal spaces")
  func profilingGrammar009SinkPathsPreserveInternalSpaces() {
    #expect(
      EnvProfileParser.parse("frames;jsonl=/tmp/a b.jsonl")?.sinks == [
        .jsonl(path: "/tmp/a b.jsonl")
      ])
  }

  @Test("stress profiling grammar 010 tabs trim every token boundary")
  func profilingGrammar010TabsTrimEveryTokenBoundary() {
    #expect(
      EnvProfileParser.parse("\tframes\t,\tmemory@1s\t;\tsummary\t")?.signals == [
        .frames, .memory(interval: .seconds(1)),
      ])
  }

  @Test("stress profiling grammar 011 newline boundaries are rejected")
  func profilingGrammar011NewlineBoundariesAreRejected() {
    #expect(EnvProfileParser.parse("\nframes\n") == nil)
  }

  @Test("stress profiling grammar 012 signal spelling remains case sensitive")
  func profilingGrammar012SignalSpellingRemainsCaseSensitive() {
    #expect(EnvProfileParser.parse("Frames") == nil)
  }

  @Test("stress profiling grammar 013 zero millisecond intervals are rejected")
  func profilingGrammar013ZeroMillisecondIntervalsAreRejected() {
    withKnownIssue("Zero memory intervals are accepted and can create an unbounded sampling loop") {
      #expect(EnvProfileParser.parse("memory@0ms") == nil)
    }
  }

  @Test("stress profiling grammar 014 zero second intervals are rejected")
  func profilingGrammar014ZeroSecondIntervalsAreRejected() {
    withKnownIssue("Zero CPU intervals are accepted and can create an unbounded sampling loop") {
      #expect(EnvProfileParser.parse("cpu@0s") == nil)
    }
  }

  @Test("stress profiling grammar 015 mixed durations cannot hide a zero total")
  func profilingGrammar015MixedDurationsCannotHideZeroTotal() {
    withKnownIssue("The duration grammar accepts a multi-component duration whose total is zero") {
      #expect(EnvProfileParser.parseDuration("0s0ms") == nil)
    }
  }

  @Test("stress profiling grammar 016 leading zeroes preserve duration value")
  func profilingGrammar016LeadingZeroesPreserveDurationValue() {
    #expect(EnvProfileParser.parseDuration("0005ms") == .milliseconds(5))
  }

  @Test("stress profiling grammar 017 seconds then milliseconds add exactly")
  func profilingGrammar017SecondsThenMillisecondsAddExactly() {
    #expect(EnvProfileParser.parseDuration("1s250ms") == .milliseconds(1_250))
  }

  @Test("stress profiling grammar 018 milliseconds then seconds add exactly")
  func profilingGrammar018MillisecondsThenSecondsAddExactly() {
    #expect(EnvProfileParser.parseDuration("250ms1s") == .milliseconds(1_250))
  }

  @Test("stress profiling grammar 019 repeated second components add exactly")
  func profilingGrammar019RepeatedSecondComponentsAddExactly() {
    #expect(EnvProfileParser.parseDuration("1s2s3s") == .seconds(6))
  }

  @Test("stress profiling grammar 020 overflowing integer components are rejected")
  func profilingGrammar020OverflowingIntegerComponentsAreRejected() {
    #expect(EnvProfileParser.parseDuration("999999999999999999999999999999s") == nil)
  }

  @Test("stress profiling grammar 021 explicit plus signs are rejected")
  func profilingGrammar021ExplicitPlusSignsAreRejected() {
    #expect(EnvProfileParser.parseDuration("+5ms") == nil)
  }

  @Test("stress profiling grammar 022 negative components are rejected")
  func profilingGrammar022NegativeComponentsAreRejected() {
    #expect(EnvProfileParser.parseDuration("-5ms") == nil)
  }

  @Test("stress profiling grammar 023 non-ASCII number characters are rejected")
  func profilingGrammar023NonASCIINumberCharactersAreRejected() {
    #expect(EnvProfileParser.parseDuration("٥ms") == nil)
  }

  @Test("stress profiling grammar 024 embedded duration whitespace is rejected")
  func profilingGrammar024EmbeddedDurationWhitespaceIsRejected() {
    #expect(EnvProfileParser.parseDuration("1s 5ms") == nil)
  }

  @Test("stress profiling grammar 025 semicolons inside sink paths reject the whole config")
  func profilingGrammar025SemicolonsInsideSinkPathsRejectWholeConfig() {
    #expect(EnvProfileParser.parse("frames;tsv=/tmp/a;b.tsv") == nil)
  }
}
