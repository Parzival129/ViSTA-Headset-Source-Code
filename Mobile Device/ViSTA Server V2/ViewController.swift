import UIKit
import Vision
import Swifter
import CoreLocation


var sys_obstacle_array = [0] as [Float32]
var sys_polyline = "NA"
var sys_longitude = 0.0
var sys_latitude = 0.0
var sys_direction = ""

class ViewController: UIViewController {
    
    @IBOutlet weak var locationField: UITextField!
    @IBOutlet weak var startRouteButtonOutlet: UIButton!
    @IBOutlet weak var LocationTextOutlet: UILabel!
    
    var local_polyline = ""
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        // setup ml model
    }
    
    @IBAction func submitLocationButton(_ sender: UIButton) {
        let locationText = locationField.text
        print(locationText ?? "Not yet")
        
        // Example usage:
        let apiKey = "AIzaSyC1SQEvJruFCtYorF6kv2pX4ihpPJjPJxw"
        let directionsAPI = GoogleMapsDirectionsAPI(apiKey: apiKey)
        
        // Access LocationServer instance from the AppDelegate
        guard let locationServer = AppDelegate.locationServer else {
            print("LocationServer not initialized.")
            return
        }
        
        let start_coords = locationServer.getLocation()

        directionsAPI.getPolylineForRoute(from: start_coords, to: locationText ?? "unknown") { polyline in
            if let polyline = polyline {
                print("Polyline: \(polyline)")
                self.local_polyline = polyline

                self.startRouteButtonOutlet.isHidden = false
            } else {
                print("Failed to retrieve polyline")
            }
        }
    }
    
    @IBAction func startRouteButton(_ sender: UIButton) {
        sys_polyline = self.local_polyline
        //sys_polyline = "ymoiGjc`cNSuA_AXa@uCkBl@YmBjDeAk@qDa@iA]}BbEqAvCbSNfARj@cB`AqAK"
    }
    
}

import Accelerate
import Foundation
import CoreML
import Vision

class LocationServer: NSObject, CLLocationManagerDelegate {
    // MARK: - Vision Properties
    private var request: VNCoreMLRequest?
    private var visionModel: VNCoreMLModel?
    private let estimationModel = try? FCRN() // Assuming FCRN is your Core ML model
    private let depthMax: Float = 4
    private var sys_depth: UIImage?
    private let locationManager = CLLocationManager()
    private var server: HttpServer?
    private var sharedImageData: Data?

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        setUpModel()

        do {
            server = try startServer()
            print("SERVER STARTED!")
        } catch {
            print("Error starting server: \(error)")
        }
    }

    func getLocation() -> String {
        let response = "\(sys_latitude),\(sys_longitude)"
        return response
    }

    func startServer() throws -> HttpServer {
        let server = HttpServer()

        // Endpoint for getting GPS coordinates
        server["/"] = { [weak self] request in
            guard let self = self else { return .internalServerError }

            if let location = self.locationManager.location {
                let latitude = location.coordinate.latitude
                let longitude = location.coordinate.longitude
                return .ok(.text("\(latitude),\(longitude)"))
            } else {
                return .internalServerError
            }
        }

        // Endpoint for getting sys_polyline
        server["/getSysPolyline"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }
            return .ok(.text(sys_polyline))
        }
        
        

        var sharedImageData: Data?
    

        server.post["/uploadAndEval"] = { [self] request in
            do {
                // Check if the request contains a file named "my_file" in the multipart form data
                if let myFileMultipart = request.parseMultiPartFormData().filter({ $0.name == "my_file" }).first {
                    // Handle file upload
                    let data = Data(myFileMultipart.body)
                    sharedImageData = data
                    //return .ok(.text("Your file has been uploaded!"))


                    // Process the UIImage as needed
                    if let uiImage = UIImage(data: sharedImageData!) {
                        //let imagePixelBuffer = convertToCVPixelBuffer(image: uiImage)
                        let imagePixelBuffer = buffer(from: uiImage)
                        
                        // Assuming LiveImageViewController is available and has a predict method
                        
                        DispatchQueue.global(qos: .userInitiated).async {
                            // Assuming LiveImageViewController is available and has a predict methode
                            //print(imagePixelBuffer)
                            self.predict(with: imagePixelBuffer!)
                        }
                        
                        // Process the image as needed
                        return .ok(.text(sys_direction))
                    } else {
                        return .badRequest(.text("Failed to create UIImage from the provided data"))
                    }
                }
            }
            return .badRequest(.text("Failed to create UIImage from the provided data"))
        }


        try server.start(8080)

        return server
    }


    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            if let location = locations.last {
                let latitude = location.coordinate.latitude
                let longitude = location.coordinate.longitude
                //print("Latitude: \(latitude), Longitude: \(longitude)")
                sys_longitude = longitude
                sys_latitude = latitude
            }
        }
    }

    // MARK: - Setup Core ML

    func setUpModel() {
        if let visionModel = try? VNCoreMLModel(for: estimationModel!.model) {
            self.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError()
        }
        }

    // MARK: - Vision

    func predict(with pixelBuffer: CVPixelBuffer) {
        guard let request = request else {
            fatalError("Core ML request not initialized")
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let error = error {
            print("Vision request error: \(error)")
            return
        }

        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let map = observations.first?.featureValue.multiArrayValue else {
            print("No observations found")
            return
        }

        guard let doubleArray = multiArrayToDoubleArray(map) else {
            print("Failed to convert MultiArray to Double array")
            return
        }
        

        // Process the double array
        //print(doubleArray.count)
        let depthMatrix = splitArrayIntoSubarrays(inputArray: doubleArray)
        let normalized_matrix = normalize(depthMatrix)
        //print(normalized_matrix)
        let histogramImage = createHistogramImage(depthImage: normalized_matrix)
        //print(histogramImage)
        let obstacle_array = createObstacleArray(array: histogramImage, threshold: 100, window: 15)
        //print(obstacle_array)
        sys_direction = determineLowerAverageSide(array: obstacle_array) ?? "stay,0"
        //print(histogramImage)
    }

    // MARK: - Utility

    func multiArrayToDoubleArray(_ multiArray: MLMultiArray) -> [Double]? {
        guard multiArray.dataType == .double else {
            print("MultiArray is not of type Double")
            return nil
        }

        let count = multiArray.count
        let pointer = UnsafeMutablePointer<Double>(OpaquePointer(multiArray.dataPointer))

        guard pointer != nil else {
            print("Failed to create pointer")
            return nil
        }

        let buffer = UnsafeBufferPointer(start: pointer, count: count)
        return Array(buffer)
    }
    
    func averageOfIndexes(from: Int, to: Int, of array: [Double]) -> Double {
        let subArray = Array(array[from...to])
        return subArray.reduce(0, +) / Double(subArray.count)
    }
    
    func findThreshold(arr: [Double], numStdDevs: Double = 1) -> Double? {
        let mean = arr.reduce(0, +) / Double(arr.count)
        let stdDev = sqrt(arr.map { pow($0 - mean, 2) }.reduce(0, +) / Double(arr.count))
        let threshold = mean - numStdDevs * stdDev
        
        return threshold
    }

    func determineLowerAverageSide(array: [Double]) -> String? {
        print("", terminator: Array(repeating: "\n", count: 100).joined())
        let average50to110 = averageOfIndexes(from: 50, to: 110, of: array)
        //let opt_threshold = findThreshold(arr:array) ?? 2.0
        let opt_threshold = 2.0
        let average0to49 = averageOfIndexes(from: 0, to: 49, of: array)
        let average111to145 = averageOfIndexes(from: 111, to: 145, of: array)
//        print("----")
//        print("THRES", opt_threshold)
//        print("MID", average50to110)
//        print("LEFT", average0to49)
//        print("RIGHT", average111to145)
        if average50to110 > opt_threshold {
            
            if average0to49 > average111to145 {
                return "right"
            }
            if average111to145 > average0to49 {
                return "left"
            }
            
        } else {
            return "stay"
        }
        return "stay"
    }
    
    func createObstacleArray(array: [[UInt8]], threshold: Int, window: Int) -> [Double] {
        var xCoords = Array(repeating: 0, count: array[0].count)
        
        for (i, row) in array.enumerated() {
            if i < threshold {
                for (j, val) in row.enumerated() {
                    if val > 5 {
                        xCoords[j] += 1
                    }
                }
            }
        }
        
        let windowArray = Array(repeating: 1.0 / Double(window), count: window)
        let finalResult = convolve1D(array: xCoords.map { Double($0) }, kernel: windowArray)
        
        return finalResult
    }

    func convolve1D(array: [Double], kernel: [Double]) -> [Double] {
        var result = [Double]()
        for i in 0...(array.count - kernel.count) {
            let slice = Array(array[i..<i + kernel.count])
            let dotProduct = zip(slice, kernel).map { $0 * $1 }.reduce(0, +)
            result.append(dotProduct)
        }
        return result
    }
    
    func splitArrayIntoSubarrays(inputArray: [Double]) -> [[Double]] {
        let subArrayLength = 160
        let numberOfSubArrays = inputArray.count / subArrayLength
        var resultArray: [[Double]] = []

        for i in 0..<numberOfSubArrays {
            let startIndex = i * subArrayLength
            let endIndex = startIndex + subArrayLength
            let subArray = Array(inputArray[startIndex..<endIndex])
            resultArray.append(subArray)
        }

        return resultArray
    }
    
    func normalize<T: BinaryFloatingPoint>(_ array: [[T]]) -> [[T]] {
        guard let minVal = array.flatMap({ $0 }).min(),
              let maxVal = array.flatMap({ $0 }).max() else {
            return array
        }
        
        return array.map { row in
            row.map { element in
                (element - minVal) * (255 / (maxVal - minVal))
            }
        }
    }
    
    func createHistogramImage(depthImage: [[Double]]) -> [[UInt8]] {
        let height = depthImage.count
        let width = depthImage[0].count
        var histograms = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: 256)

        for col in 0..<width {
            var hist = [Int](repeating: 0, count: 256)
            for row in 0..<height {
                let value = Int(depthImage[row][col])
                hist[value] += 1
            }

            for i in 0..<256 {
                histograms[i][col] = UInt8(min(max(hist[i], 0), 255))
            }
        }

        return histograms
    }
}

class GoogleMapsDirectionsAPI {
    
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func getPolylineForRoute(from: String, to: String, completion: @escaping (String?) -> Void) {
        guard let url = buildDirectionsURL(from: from, to: to) else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let routes = json["routes"] as? [[String: Any]],
                   let firstRoute = routes.first,
                   let polylineData = firstRoute["overview_polyline"] as? [String: String],
                   let polyline = polylineData["points"] {
                    completion(polyline)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    private func buildDirectionsURL(from: String, to: String) -> URL? {
        let baseURL = "https://maps.googleapis.com/maps/api/directions/json"
        let origin = from.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let destination = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "\(baseURL)?origin=\(origin)&destination=\(destination)&key=\(apiKey)"
        return URL(string: urlString)
    }
}




func convertToCVPixelBuffer(image: UIImage) -> CVPixelBuffer? {
    // Ensure the image is in the correct orientation
    guard let cgImage = image.cgImage else {
        return nil
    }

    let imageWidth = cgImage.width
    let imageHeight = cgImage.height

    let options: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     imageWidth,
                                     imageHeight,
                                     kCVPixelFormatType_32ARGB,
                                     options as CFDictionary,
                                     &pixelBuffer)

    guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    let pixelData = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: pixelData,
                                  width: imageWidth,
                                  height: imageHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer),
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
        return nil
    }

    context.concatenate(CGAffineTransform.identity)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

    return unwrappedPixelBuffer
}


func buffer(from image: UIImage) -> CVPixelBuffer? {
  let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
  var pixelBuffer : CVPixelBuffer?
  let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
  guard (status == kCVReturnSuccess) else {
    return nil
  }

  CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
  let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

  let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

  context?.translateBy(x: 0, y: image.size.height)
  context?.scaleBy(x: 1.0, y: -1.0)

  UIGraphicsPushContext(context!)
  image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
  UIGraphicsPopContext()
  CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

  return pixelBuffer
}

func convertFloat32ToDouble(float32Array: MLMultiArray) -> MLMultiArray? {
    // Ensure the original array is of type Float32
    guard float32Array.dataType == .float32 else {
        return nil
    }

    // Create a new MLMultiArray of type Double with the same shape
    guard let doubleArray = try? MLMultiArray(shape: float32Array.shape, dataType: .double) else {
        return nil
    }

    // Get the UnsafeMutablePointer to the data of both arrays
    guard let float32Pointer = float32Array.dataPointer.bindMemory(to: Float32.self, capacity: float32Array.count) as UnsafeMutablePointer<Float32>?,
          let doublePointer = doubleArray.dataPointer.bindMemory(to: Double.self, capacity: doubleArray.count) as UnsafeMutablePointer<Double>? else {
        return nil
    }

    // Convert the values from Float32 to Double
    vDSP_vspdp(float32Pointer, 1, doublePointer, 1, vDSP_Length(float32Array.count))

    return doubleArray
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    static var locationServer: LocationServer?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        AppDelegate.locationServer = LocationServer()
        return true
    }
}
