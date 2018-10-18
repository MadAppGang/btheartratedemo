//
//  ViewController.swift
//  HRBluetoothSensor
//
//  Created by Sergii Kostanian on 10/17/18.
//  Copyright © 2018 MAG. All rights reserved.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController {

    // https://www.bluetooth.com/specifications/gatt/services
    let heartRateUUID = CBUUID(string: "180D")
    // https://www.bluetooth.com/specifications/gatt/characteristics
    let heartRateCharacteristicUUID = CBUUID(string: "2A37")
    
    // CBCentralManager reference should be a strong reference to the class as a member variable. It cannot work as a local reference
    var centralManager: CBCentralManager!
    
    var heartRateSensor: CBPeripheral?
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. Create Manager
        centralManager = CBCentralManager(delegate: self, queue: nil)        
    }
}

extension ViewController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            
            // 2. Start discovering bluetooth sensors that can read heart rate or retrive from centralManager
            if let sensor = centralManager.retrieveConnectedPeripherals(withServices: [heartRateUUID]).first { 
            
                // 3. Store reference to a sensor
                heartRateSensor = sensor
                
                // 4. Establish local connection to a sensor
                central.connect(sensor, options: nil)
                
                // NOTE: The list of connected peripherals returned from retrieveConnectedPeripherals can include those that are connected by other apps and that will need to be connected locally using the connect(_:options:) method before they can be used.
            } else {
                central.scanForPeripherals(withServices: [heartRateUUID], options: nil)
            }
            
        default:
            break
        }
        
        // NOTE: You should call scanForPeripherals after poweredOn state, otherwise you will get:
        // API MISUSE: <CBCentralManager: 0x1c4462180> can only accept this command while in the powered on state
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {        
        
        // 3. Store reference to a sensor and stop scanning
        heartRateSensor = peripheral
        central.stopScan()
        
        // NOTE: Once the peripheral is found, you should store a reference to it, otherwise you will get API misuse warning.
        
        // 4. Establish local connection to a discovered sensor
        central.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        // 5. Become delegate of a connected sensor
        peripheral.delegate = self
        
        // 6. Discover heart rate service
        peripheral.discoverServices([heartRateUUID])        
    }
}

extension ViewController: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == heartRateUUID }) else { return }
        
        // 7. Discover heart rate characteristic
        peripheral.discoverCharacteristics([heartRateCharacteristicUUID], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == heartRateCharacteristicUUID }) else { return }
        
        // 8. Start receiving heart rate
        peripheral.setNotifyValue(true, for: characteristic)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        // 9. Get heart rate raw data 
        guard let binaryData = characteristic.value else { return }
        var bytes = [UInt8](repeating: 0, count: binaryData.count)
        binaryData.copyBytes(to: &bytes, count: bytes.count)
        
        // 10. Extract heart rate 
        let heartRate = self.extractHeartRate(from: bytes)

        print(heartRate)
    }
    
    
    
    
    /**
     Property represents a set of bits, which values describe markup for bytes in heart rate data.
     
     Bits grouped like `| 000 | 0 | 0 | 00 | 0 |` where: 3 bits are reserved, 1 bit for RR-Interval, 1 bit for Energy Expended Status, 2 bits for Sensor Contact Status, 1 bit for Heart Rate Value Format
     */
    private func extractHeartRate(from bytes: [UInt8]) -> UInt8 {
        let flags = bytes[0]
        
        var range: Range<Int>
        
        var heartRate: UInt8
        if flags & 0x1 == 0 {
            range = 1..<(1 + MemoryLayout<UInt8>.size)
            heartRate = UInt8(bytes[1])
        } else {
            range = 1..<(1 + MemoryLayout<UInt16>.size)
            heartRate = UInt8(UnsafePointer(Array(bytes[range])).withMemoryRebound(to: UInt16.self, capacity: 1, { $0.pointee }))
        }
        
        /// 0, 1 – if value not available, 2 - if sensor is not worn, 3 - if sensor worn
        let sensorContactStatusValue = (Int(flags) >> 1) & 0x3
        if sensorContactStatusValue == 2 {
            heartRate = 0
        }
        
        return heartRate
    }
}

