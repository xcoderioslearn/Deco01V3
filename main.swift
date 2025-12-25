import Foundation
import IOKit.hid
import CoreGraphics

let VENDOR_ID: Int32 = 0x28BD
let PRODUCT_ID: Int32 = 0x0947
let MAX_TAB_X: Float = 50800.0
let MAX_TAB_Y: Float = 31750.0
let MAX_PRESS: Float = 8191.0

let mainDisplay = CGMainDisplayID()
let screen = CGDisplayBounds(mainDisplay)
let screenW = Float(screen.width)
let screenH = Float(screen.height)

var isDown = false
var lastPoint = CGPoint.zero
let eventSource = CGEventSource(stateID: .privateState)

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [kIOHIDVendorIDKey: VENDOR_ID, kIOHIDProductIDKey: PRODUCT_ID]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)



let callback: IOHIDReportCallback = { (context, result, sender, type, reportID, report, len) in
    let data = Data(bytes: report, count: len)
    if reportID == 7 && len >= 10 {
        let status = data[1]
        let tipPressed = (status & 0x01) != 0
        let inRange = (status & 0x20) != 0
        
        if !inRange { return }

        let rawX = Float(UInt16(data[2]) | (UInt16(data[3]) << 8))
        let rawY = Float(UInt16(data[4]) | (UInt16(data[5]) << 8))
        let rawP = Float(UInt16(data[6]) | (UInt16(data[7]) << 8))
        
        let posX = CGFloat((rawX / MAX_TAB_X) * screenW)
        let posY = CGFloat((rawY / MAX_TAB_Y) * screenH)
        let newPoint = CGPoint(x: posX, y: posY)
        let pressure = Double(rawP / MAX_PRESS)
        let penTouching = tipPressed && pressure > 0.04
        let eventType: CGEventType
        if penTouching {
            eventType = isDown ? .leftMouseDragged : .leftMouseDown
            isDown = true
        } else {
            eventType = isDown ? .leftMouseUp : .mouseMoved
            isDown = false
        }
        
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: eventType, mouseCursorPosition: newPoint, mouseButton: .left) {
            event.setDoubleValueField(.mouseEventPressure, value: pressure)
            event.setIntegerValueField(.mouseEventSubtype, value: 1)
            event.setIntegerValueField(CGEventField(rawValue: 42)!, value: 1337)

            if isDown {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
            }

            event.post(tap: .cghidEventTap)
        }
        lastPoint = newPoint
    }
}
IOHIDManagerRegisterInputReportCallback(manager, callback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)


let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
if openStatus == kIOReturnSuccess {
    print("Deco 01 V3: manual driver started")
    CFRunLoopRun()
}
