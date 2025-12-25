import Foundation
import IOKit.hid
import CoreGraphics
import AppKit

let VENDOR_ID: Int32 = 0x28BD
let PRODUCT_ID: Int32 = 0x0947
let MAX_TAB_X: Float = 50800.0
let MAX_TAB_Y: Float = 31750.0
let MAX_PRESS: Float = 8191.0

let NX_SUBTYPE_TABLET_POINT: Int16 = 1
let NX_SUBTYPE_TABLET_PROXIMITY: Int16 = 2

var isDown = false
var isNearby = false
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
        
        guard let mainScreen = NSScreen.main else { return }
        let scale = CGFloat(mainScreen.backingScaleFactor)
        let screenW = Float(mainScreen.frame.width)
        let screenH = Float(mainScreen.frame.height)

        if inRange && !isNearby {
            if let prox = CGEvent(source: eventSource) {
                prox.type = .tabletProximity
                prox.setIntegerValueField(CGEventField(rawValue: 107)!, value: 1)
                prox.setIntegerValueField(CGEventField(rawValue: 110)!, value: 1)
                prox.setIntegerValueField(.mouseEventSubtype, value: Int64(NX_SUBTYPE_TABLET_PROXIMITY))
                prox.post(tap: .cghidEventTap)
            }
            isNearby = true
        } else if !inRange && isNearby {
            isNearby = false
            return
        }

        if !inRange { return }

        let rawX = Float(UInt16(data[2]) | (UInt16(data[3]) << 8))
        let rawY = Float(UInt16(data[4]) | (UInt16(data[5]) << 8))
        let rawP = Float(UInt16(data[6]) | (UInt16(data[7]) << 8))
        
        let normX = max(0, min(1, rawX / MAX_TAB_X))
        let normY = max(0, min(1, rawY / MAX_TAB_Y))
        
        let posX = CGFloat(normX) * CGFloat(screenW) * scale
        let posY = CGFloat(normY) * CGFloat(screenH) * scale
        let pressure = Double(rawP / MAX_PRESS)
        
        let penTouching = tipPressed && pressure > 0.05
        let eventType: CGEventType = penTouching ? (isDown ? .leftMouseDragged : .leftMouseDown) : (isDown ? .leftMouseUp : .mouseMoved)
        isDown = penTouching
        
        let point = CGPoint(x: posX, y: posY)
        if let event = CGEvent(mouseEventSource: eventSource, mouseType: eventType, mouseCursorPosition: point, mouseButton: .left) {
            
            event.setDoubleValueField(.mouseEventPressure, value: pressure)
            event.setIntegerValueField(.mouseEventSubtype, value: Int64(NX_SUBTYPE_TABLET_POINT))
            
            event.setIntegerValueField(.tabletEventPointX, value: Int64(normX * 65535))
            event.setIntegerValueField(.tabletEventPointY, value: Int64(normY * 65535))
            event.setIntegerValueField(.tabletEventPointPressure, value: Int64(pressure * 65535))
            
            event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 1)
            event.setIntegerValueField(CGEventField(rawValue: 42)!, value: 1337)

            if isDown {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
            }

            event.post(tap: .cghidEventTap)
        }
    }
}

IOHIDManagerRegisterInputReportCallback(manager, callback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess {
    print("Deco 01 V3: Blender Driver Started ")
    CFRunLoopRun()
}
