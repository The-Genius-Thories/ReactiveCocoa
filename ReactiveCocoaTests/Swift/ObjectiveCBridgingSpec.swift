//
//  ObjectiveCBridgingSpec.swift
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2015-01-23.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import LlamaKit
import Nimble
import Quick
import ReactiveCocoa

class ObjectiveCBridgingSpec: QuickSpec {
	override func spec() {
		describe("RACSignal.asSignalProducer") {
			it("should subscribe once per start()") {
				var subscriptions = 0

				let racSignal = RACSignal.createSignal { subscriber in
					subscriber.sendNext(subscriptions++)
					subscriber.sendCompleted()

					return nil
				}

				let producer = racSignal.asSignalProducer() |> map { $0 as Int }

				expect((producer |> single)?.value).to(equal(0))
				expect((producer |> single)?.value).to(equal(1))
				expect((producer |> single)?.value).to(equal(2))
			}

			it("should forward errors")	{
				let error = TestError.Default.nsError

				let racSignal = RACSignal.error(error)
				let producer = racSignal.asSignalProducer()
				let result = producer |> last

				expect(result?.error).to(equal(error))
			}
		}

		describe("asRACSignal") {
			describe("on a Signal") {
				it("should forward events") {
					let (signal, sink) = Signal<NSNumber, NoError>.pipe()
					let racSignal = asRACSignal(signal)

					var lastValue: NSNumber?
					var didComplete = false

					racSignal.subscribeNext({ number in
						lastValue = number as? NSNumber
					}, completed: {
						didComplete = true
					})

					expect(lastValue).to(beNil())

					for number in [1, 2, 3] {
						sendNext(sink, number)
						expect(lastValue).to(equal(number))
					}

					expect(didComplete).to(beFalse())
					sendCompleted(sink)
					expect(didComplete).to(beTrue())
				}

				it("should convert errors to NSError") {
					let (signal, sink) = Signal<AnyObject, TestError>.pipe()
					let racSignal = asRACSignal(signal)

					let expectedError = TestError.Error2
					var error: NSError?

					racSignal.subscribeError {
						error = $0
						return
					}

					sendError(sink, expectedError)

					expect(error?.domain).to(equal(TestError.domain))
					expect(error?.code).to(equal(expectedError.rawValue))
				}
			}

			describe("on a SignalProducer") {
				it("should start once per subscription") {
					var subscriptions = 0

					let producer = SignalProducer<NSNumber, NoError>.try {
						return success(subscriptions++)
					}
					let racSignal = asRACSignal(producer)

					expect(racSignal.first() as? NSNumber).to(equal(0))
					expect(racSignal.first() as? NSNumber).to(equal(1))
					expect(racSignal.first() as? NSNumber).to(equal(2))
				}

				it("should convert errors to NSError") {
					let producer = SignalProducer<AnyObject, TestError>(error: .Error1)
					let racSignal = asRACSignal(producer).materialize()

					let event = racSignal.first() as? RACEvent

					expect(event?.error.domain).to(equal(TestError.domain))
					expect(event?.error.code).to(equal(TestError.Error1.rawValue))
				}
			}
		}

		describe("RACCommand.asAction") {
			var command: RACCommand!
			var results: [Int] = []

			var enabledSubject: RACSubject!
			var enabled = false

			var action: Action<AnyObject?, AnyObject?, NSError>!

			beforeEach {
				enabledSubject = RACSubject()
				results = []

				command = RACCommand(enabled: enabledSubject) { (input: AnyObject?) -> RACSignal! in
					let inputNumber = input as Int
					return RACSignal.`return`(inputNumber + 1)
				}

				expect(command).notTo(beNil())

				command.enabled.subscribeNext { enabled = $0 as Bool }
				expect(enabled).to(beTruthy())

				command.executionSignals.flatten().subscribeNext { results.append($0 as Int) }
				expect(results).to(equal([]))

				action = command.asAction()
			}

			it("should reflect the enabledness of the command") {
				expect(action.enabled.value).to(beTruthy())

				enabledSubject.sendNext(false)
				expect(enabled).toEventually(beFalsy())
				expect(action.enabled.value).to(beFalsy())
			}

			it("should execute the command once per start()") {
				let producer = action.apply(0)
				expect(results).to(equal([]))

				producer |> wait
				expect(results).to(equal([ 1 ]))

				producer |> wait
				expect(results).to(equal([ 1, 1 ]))

				let otherProducer = action.apply(2)
				expect(results).to(equal([ 1, 1 ]))

				otherProducer |> wait
				expect(results).to(equal([ 1, 1, 3 ]))

				producer |> wait
				expect(results).to(equal([ 1, 1, 3, 1 ]))
			}
		}

		describe("asRACCommand") {
			var action: Action<AnyObject?, NSString, TestError>!
			var results: [NSString] = []

			var enabledProperty: MutableProperty<Bool>!

			var command: RACCommand!
			var enabled = false
			
			beforeEach {
				results = []
				enabledProperty = MutableProperty(false)

				action = Action(enabledIf: enabledProperty) { input in
					let inputNumber = input as Int
					return SignalProducer(value: "\(inputNumber + 1)")
				}

				expect(action.enabled.value).to(beFalsy())

				action.values.observe(next: { results.append($0) })

				command = asRACCommand(action)
				expect(command).notTo(beNil())

				command.enabled.subscribeNext { enabled = $0 as Bool }
				expect(enabled).to(beFalsy())
			}

			it("should reflect the enabledness of the action") {
				enabledProperty.value = true
				expect(enabled).toEventually(beTruthy())

				enabledProperty.value = false
				expect(enabled).toEventually(beFalsy())
			}

			it("should apply and start a signal once per execution") {
				let signal = command.execute(0)

				signal.waitUntilCompleted(nil)
				expect(results).to(equal([ "1" ]))

				signal.waitUntilCompleted(nil)
				expect(results).to(equal([ "1" ]))

				command.execute(2).waitUntilCompleted(nil)
				expect(results).to(equal([ "1", "3" ]))
			}
		}
	}
}
