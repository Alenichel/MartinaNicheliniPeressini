//
//  HealthKitBridge.swift
//  data4help
//
//  Created by Alessandro Nichelini on 12/12/2018.
//  Copyright © 2018 Francesco Peressini. All rights reserved.
//
import Foundation
import HealthKit
import UserNotifications
import UIKit

func getThreshold() -> String {
    if let tok = Global.userDefaults.string(forKey: "threshold") {
        print(tok)
        return tok
    } else {
        print(String(Global.DEFAULT_THRESHOLD))
        return String(Global.DEFAULT_THRESHOLD)
    }
}

class AutomatedSoS: NSObject {
    
    private static func timerDone(){
        print("timer done action triggered")
        DispatchQueue.main.async {
            let mainController = UIApplication.shared.keyWindow?.rootViewController?.presentedViewController
            let vc = mainController?.storyboard?.instantiateViewController(withIdentifier: "sos") as! SOSViewController
            mainController!.present(vc, animated: true, completion: nil)
            }
        //}
    } //end method timerDone
    
    private static func notificationAlert(badValue: HKQuantitySample){
        print("SOS handler triggered")
        
        let content = UNMutableNotificationContent()
        content.title = Messages.BPM_ALERT_TITLE
        content.body = Messages.BPM_ALERT_BODY
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = Global.SOSCategoryID
        
        //schedule notification with a trigger of a time interval of 1 second
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "SOSNotificationIdentifier"
        
        //make a request to the notification center
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content, trigger: trigger)
        center.add(request, withCompletionHandler: { (error) in
            if let error = error {print(error)}})
        timerDone()
        
    } //end method notificationAlert
    
    public static func checkValues (values: [HKQuantitySample]) -> [Int] {
        var notToSend : [Int] = []
        var toSendWithSOSFlag : [HKQuantitySample] = []
        let threshHold = Int(getThreshold())
        var index = 0;
        for value in values {
            let tmp = "\(value.quantity)"
            let count = Int(tmp.split(separator: " ")[0])
            if count ?? 0 < threshHold! {
                self.notificationAlert(badValue: value)
                notToSend.append(index)
                toSendWithSOSFlag.append(value)
            } //end if check threshHold
            index = index + 1
        }//end for
        HTTPManager.sendHeartData(data: toSendWithSOSFlag, true)
        return notToSend
    } //end method checkValues
} //end class automatedSOS

class HealthKitManager {
    
    static public var lastHertQueryData : [HeartData] = []
    
    static private let healthStore = HKHealthStore()
    
    static func getHealthStore() -> HKHealthStore {
        return healthStore
    }
    
    public static func checkIfHealtkitIsEnabled (_ notAuthNotificationHandler: @escaping ((Bool) -> ())) {
        let authStatus = healthKitStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .heartRate)!)
        if authStatus == HKAuthorizationStatus.notDetermined || authStatus == HKAuthorizationStatus.sharingDenied {
            notAuthNotificationHandler(false)
        } else { notAuthNotificationHandler(true)}
    }
    
    public static func activateLongRunningQuery() {
        
        // check if HK is enabled
        var HKEnabled = Bool()
        checkIfHealtkitIsEnabled({ enabled in HKEnabled = enabled})
        if !HKEnabled {return}
        
        let sampleType = HKObjectType.quantityType(forIdentifier: .heartRate)
        
        let query = HKObserverQuery(sampleType: sampleType!, predicate: nil) {
            query, completionHandler, error in
            if error != nil {
                print("*** An error occured ***")
                abort()
            }
            
            // Take whatever steps are necessary to update your app's data and UI
            // This may involve executing other queries
            //HTTPManager.sendHeartData(data: HealthKitManager.getLastHeartBeat())
            
            DispatchQueue.main.async(execute: {
                print("Async work\n")
                HealthKitManager.getLastHeartBeat({ retrievedData in
                    var toSend = retrievedData
                    let check = UserDefaults.standard.bool(forKey: "automatedSOSToggle")
                    if check {
                        var notToSend : [Int] = AutomatedSoS.checkValues(values: retrievedData)
                        for value in notToSend {
                            toSend.remove(at: value)
                        } //end for
                    } //end check for automatedSOS status
                    HTTPManager.sendHeartData(data: toSend)
            })})
            
            print("Triggered by long running query")
            
            // If you have subscribed for background updates you must call the completion handler here.
            completionHandler()
        }
        
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: HKObjectType.quantityType(forIdentifier: .heartRate)!, frequency: .immediate, withCompletion: {_, error in if error == nil {print ("Background delivery activated")}})
    }
    
    
    static func getLastHeartBeat (_ updateHandler: @escaping ([HKQuantitySample]) -> ()) {
        let lastUpdateDate = UserDefaults.standard.object(forKey: "timestampOfLastDataRetrieved")
        
        let myStartDate : Date
        let myEndDate = Date()
        if lastUpdateDate == nil { myStartDate = myEndDate.addingTimeInterval(-(60*60*24))} else {
            myStartDate = (lastUpdateDate as! Date).addingTimeInterval(1) }

        let timeIntervalPredicate =
            HKQuery.predicateForSamples(withStart: myStartDate,
                                        end: myEndDate, options: [])
        
        let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate)
        
        var samples = [HKQuantitySample]()
        let descriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: sampleType!, predicate: timeIntervalPredicate, limit: Int(Global.QUERY_LIMIT), sortDescriptors: [descriptor]) {
            query, results, error in
            //Controlla se è stata data l'autorizzazione!!!
            samples = results as! [HKQuantitySample]
            updateHandler(samples)
            
            // If I've found some elements, I save the date of the last of them in order to have a reference of the timestamp of the last retrieved sample
            if samples.count != 0 {
                let lastTimestamp = samples[samples.count - 1].startDate
                UserDefaults.standard.set(lastTimestamp, forKey: "timestampOfLastDataRetrieved")
            }
        }
        healthStore.execute(query)
    }
}
