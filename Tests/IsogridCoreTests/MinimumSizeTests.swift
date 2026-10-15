import Testing
@testable import IsogridCore

struct MinimumSizeTests {
    @Test func aWindowThatStopsShortIsAtItsMinimum() {
        #expect(MinimumSize.update(0, asked: 500, kept: 663) == 663)
    }

    @Test func roundingToWholeStepsIsNotAMinimum() {
        #expect(MinimumSize.update(0, asked: 500, kept: 511) == 0)
        #expect(MinimumSize.update(0, asked: 500, kept: 489) == 0)
    }

    @Test func aWindowThatAcceptsAsMuchKeepsWhatIsKnown() {
        #expect(MinimumSize.update(663, asked: 700, kept: 700) == 663)
    }

    @Test func goingSmallerThanTheKnownMinimumForgetsIt() {
        #expect(MinimumSize.update(663, asked: 500, kept: 500) == 0)
    }
}
