import Testing
@testable import Headroom

@Suite struct StatisticsTests {
    @Test func medianOfOddAndEvenCounts() {
        #expect(Statistics.median([3, 1, 2]) == 2)
        #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
        #expect(Statistics.median([7]) == 7)
    }

    @Test func bootstrapIntervalBracketsTheMedian() {
        let samples = [55.0, 57, 58, 58.5, 59, 59.2, 60, 60.5, 61, 63]
        let interval = Statistics.bootstrapMedianInterval(samples)
        let median = Statistics.median(samples)
        #expect(interval.lowerBound <= median && median <= interval.upperBound)
        #expect(interval.lowerBound >= samples.min()! && interval.upperBound <= samples.max()!)
    }

    @Test func bootstrapIsDeterministicForAGivenSeed() {
        let samples = [1.0, 2, 3, 4, 5, 6, 7]
        let first = Statistics.bootstrapMedianInterval(samples)
        let second = Statistics.bootstrapMedianInterval(samples)
        #expect(first == second)
        let other = Statistics.bootstrapMedianInterval(samples, seed: 7)
        #expect(other.lowerBound <= other.upperBound)
    }

    @Test func constantSamplesGiveADegenerateInterval() {
        let interval = Statistics.bootstrapMedianInterval([42, 42, 42, 42])
        #expect(interval.lowerBound == 42 && interval.upperBound == 42)
        #expect(Statistics.bootstrapMedianInterval([9]) == 9...9)
    }

    @Test func splitMix64MatchesTheReferenceSequence() {
        // First outputs of Vigna's reference implementation for seed 0.
        var generator = SplitMix64(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
    }
}
