//
//  ViewModel+Scrolling.swift
//  Squirrel
//
//  Created by A. Zheng (github.com/aheze) on 1/31/23.
//  Copyright © 2023 A. Zheng. All rights reserved.
//

import Carbon.HIToolbox
import Cocoa

extension ViewModel {
    func processKey(event: NSEvent) {
        switch Int(event.keyCode) {
            case kVK_Escape:
                if scrollInteraction != nil {
                    allowMomentumScroll = false
                }
                stopScroll()
            default:
                break
        }
    }

    func stopScroll() {
        timer?.invalidate()
        timer = nil

        if let scrollInteraction {
            self.scrollInteraction = nil

            if let event = CGEvent(source: nil) {
                let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: event.location, mouseButton: .left)
                mouseUp?.post(tap: .cghidEventTap)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let mouseMoved = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: scrollInteraction.initialPoint, mouseButton: .left)
                    mouseMoved?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    func processScroll(event: NSEvent) {
        guard enabled else {
            stopScroll()
            return
        }

        /// `NSEvent.mouseLocation` seems to be more accurate than `event.locationInWindow`
        let point = convertPointToScreen(point: NSEvent.mouseLocation)
        let (simulatorFrames, ignoredFrames) = getSimulatorWindowFrames()

        /// Just in case another window overlaps the simulator.
        guard !ignoredFrames.contains(where: { $0.contains(point) }) else {
            return
        }

        if !allowMomentumScroll {
            if event.momentumPhase == .changed {
                return
            }
        }

        if event.momentumPhase == .ended {
            allowMomentumScroll = true
        }

        scrollEventActivityCounter.send()

        let shouldContinue: Bool = {
            let intersectingFrame = simulatorFrames.first(where: { $0.contains(point) })

            if let intersectingFrame {
                guard let screen = getScreenWithMouse() else {
                    return false
                }

                let screenHeightToWidthRatio = screen.frame.height / screen.frame.width
                let simulatorHeightToWidthRatio = intersectingFrame.height / intersectingFrame.width

                /// if the ratios match, the simulator is in full screen mode.
                if simulatorHeightToWidthRatio > screenHeightToWidthRatio {
                    var insetFrame = intersectingFrame
                    insetFrame.origin.x += deviceBezelInsetLeft
                    insetFrame.origin.y += deviceBezelInsetTop
                    insetFrame.size.width -= deviceBezelInsetLeft + deviceBezelInsetRight
                    insetFrame.size.height -= deviceBezelInsetTop + deviceBezelInsetBottom

                    let contains = insetFrame.contains(point)

                    if !contains {
                        return false
                    }
                }

                return true
            } else {
                return false
            }
        }()

        guard shouldContinue else {
            if scrollInteraction != nil {
                /// Stop further momentum scroll events from triggering.
                allowMomentumScroll = false

                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    self.fireTimer()
                }
            }

            return
        }

        let delta: CGFloat = {
            if naturalScrolling {
                return event.scrollingDeltaY
            } else {
                return event.scrollingDeltaY * -1
            }
        }()

        if var scrollInteraction {
            scrollInteraction.targetDelta += delta

            let deltaPerStep = (scrollInteraction.targetDelta - scrollInteraction.deltaCompleted) / CGFloat(numberOfScrollSteps)
            scrollInteraction.deltaPerStep = deltaPerStep

            self.scrollInteraction = scrollInteraction

        } else {
            let deltaPerStep = delta / CGFloat(numberOfScrollSteps)
            let scrollInteraction = ScrollInteraction(
                initialPoint: point,
                targetDelta: delta,
                deltaPerStep: deltaPerStep
            )
            self.scrollInteraction = scrollInteraction

            let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)

            timer = Timer.scheduledTimer(withTimeInterval: scrollInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.fireTimer()
            }
        }
    }

    func fireTimer() {
        guard let scrollInteraction = scrollInteraction else { return }
        guard !scrollInteraction.isComplete else {
            stopScroll()
            return
        }

        let targetPoint = CGPoint(
            x: scrollInteraction.initialPoint.x,
            y: scrollInteraction.initialPoint.y + scrollInteraction.deltaCompleted + scrollInteraction.deltaPerStep
        )
        let mouseDrag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: targetPoint, mouseButton: .left)
        mouseDrag?.post(tap: .cghidEventTap)

        self.scrollInteraction?.deltaCompleted += scrollInteraction.deltaPerStep
    }
}
