//  XcodeManager.swift
//
//  Copyright (c) 2018, ShouDong Zheng
//  All rights reserved.

//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:

//  * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.

//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.

//  * Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.

//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation
import SwiftyJSON

public struct XcodeManager {
    
    /// cached in memory
    private var _cacheProjet: JSON = JSON()
    private var _hashTag: Int = Int()
    private var _filePath: String = String()
    
    /// main group UUID
    private var _mainGroupUUID: String = String()
    /// root object uuid
    private var _rootObjectUUID: String = String()
    /// current project name
    private var _currentProjectName: String = String()
    /// need print log ?
    private var _isPrintLog = true
    
    public enum CodeSignStyleType: String {
        case automatic = "Automatic"
        case manual = "Manual"
    }
    
    private enum XcodeManagerLogType: String {
        case debug = "XcodeManagerDebug"
        case info = "XcodeManagerInfo"
        case error = "XcodeManagerError"
    }
    
    private enum XcodeManagerError: Error {
        case invalidParameter(code: Int , reason: String)
        case failedInitialized(code :Int, reason: String)
    }
    
    public init(projectFile: String, printLog: Bool = true) throws {
        self._isPrintLog = printLog
        do {
            _ = try self.parseProject(projectFile)
        }catch {
            xcodeManagerPrintLog("\(error)", type: .error)
            throw error
        }
    }
    
    public mutating func initProject(projectFile: String, printLog: Bool = true) throws {
        self._isPrintLog = printLog
        do {
            _ = try self.parseProject(projectFile)
        }catch {
            xcodeManagerPrintLog("\(error)", type: .error)
            throw error
        }
    }
    
    /// parse ProjectFile
    private mutating func parseProject(_ filePath: String) throws -> JSON {
        
        if (filePath.isEmpty || !FileManager.default.fileExists(atPath: filePath)) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            throw XcodeManagerError.invalidParameter(code: 600, reason: "file not found!")
        }
        
        var fileUrl = URL(fileURLWithPath: filePath)
        
        if (!fileUrl.isFileURL) {
            throw XcodeManagerError.failedInitialized(code: 600, reason: "read project file failed.")
        }
        
        if fileUrl.pathExtension == "xcodeproj" {
            fileUrl.appendPathComponent("project.pbxproj")
        }
        
        do {
            let fileData = try Data(contentsOf: fileUrl)
            
            let totalHashValue = fileData.hashValue ^ filePath.hashValue &* 1024
            
            if (self._hashTag == totalHashValue && !self._cacheProjet.isEmpty) {
                return self._cacheProjet
            }
            
            self._filePath = filePath
            self._hashTag = totalHashValue
            
            let data = try PropertyListSerialization.propertyList(from: fileData, options: .mutableContainersAndLeaves, format: nil)
            self._cacheProjet = JSON(data)
            self._rootObjectUUID = self._cacheProjet["rootObject"].string ?? String()
            let obj = self._cacheProjet["objects"].dictionary ?? Dictionary()
            let rootObject = obj[self._rootObjectUUID]?.dictionary ?? Dictionary()
            self._mainGroupUUID = rootObject["mainGroup"]?.string ?? String()
            
            if (rootObject.isEmpty || self._mainGroupUUID.isEmpty) {
                xcodeManagerPrintLog("read project file failed. error: file data is incomplete", type: .error)
                throw XcodeManagerError.failedInitialized(code: 601, reason: "file data is incomplete!")
            }
            
            for (_, value) in rootObject {
                if (!value.isEmpty) {
                    if (value["isa"].stringValue == "PBXNativeTarget" &&
                        value["productType"].stringValue == "com.apple.product-type.application") {
                        self._currentProjectName = value["name"].stringValue
                        break
                    }
                }
            }
            return self._cacheProjet
        } catch {
            xcodeManagerPrintLog("read project file failed. error: \(error.localizedDescription)", type: .error)
            throw XcodeManagerError.failedInitialized(code: 601, reason: "read project file failed.\(error)")
        }
    }
    
    private func saveProject(fileURL: URL, withPropertyList list: Any) -> Bool {
        let url = fileURL
        
        func handleEncode(fileURL: URL) -> Bool {
            func encodeString(_ str: String) -> String {
                var result = String()
                for scalar in str.unicodeScalars {
                    if (scalar.value > 0x4e00 && scalar.value < 0x9fff) {
                        result += String(format: "&#%04d;", scalar.value)
                    } else {
                        result += scalar.description
                    }
                }
                return result
            }
            do {
                var txt = try String(contentsOf: fileURL, encoding: .utf8)
                txt = encodeString(txt)
                try txt.write(to: fileURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                xcodeManagerPrintLog("Translate chinese characters to mathematical symbols error: \(error.localizedDescription)", type: .error)
                return false
            }
        }
        
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            return handleEncode(fileURL: url)
        } catch {
            xcodeManagerPrintLog("Save project file failed: \(error.localizedDescription)", type: .error)
            return false
        }
    }
    
    /// Get all objects uuid
    private func getAllUUIDs(_ projectDict: JSON) -> Array<String> {
        let objects = projectDict["objects"].dictionaryObject ?? Dictionary()
        
        var uuids = Array<String>()
        
        objects.forEach { (key, value) in
            if (key.lengthOfBytes(using: .utf8) == 24) {
                uuids.append(key)
            }
        }
        
        return uuids
    }
    
    
    /// Generate a new uuid
    private func generateUUID() -> String {
        if (self._cacheProjet.isEmpty) {
            // cache empty!
            xcodeManagerPrintLog("Please use the 'init()' initialize!", type: .error)
            return String()
        }
        
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").suffix(24).uppercased()
        let array = self.getAllUUIDs(self._cacheProjet)
        if (array.index(of: uuid) ?? -1 >= 0) {
            return generateUUID()
        }
        return uuid
    }
    
    
    /// in project root node generate the 'PBX' group, mount and write in memory cache
    ///
    /// - Parameter name: needed generate the 'PBX' group
    /// - Returns: return a new uuid with added 'PBX' group
    private mutating func generatePBXGroup(name: String) -> String {
        if (name.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return String()
        }
        let newUUID = self.generateUUID()
        let newDict = [
            "children": [],
            "isa": "PBXGroup",
            "name": name,
            "sourceTree": "<group>",
            "path": String(format: "%@/%@", _currentProjectName, name)
            ] as [String : Any]
        self._cacheProjet["objects"][newUUID] = JSON(newDict)
        
        var mainGroupObj = self._cacheProjet["objects"][self._mainGroupUUID]
        var mainGroupObjChildren = mainGroupObj["children"].arrayObject ?? Array()
        if (mainGroupObjChildren.isEmpty) {
            xcodeManagerPrintLog("Parsed mainGroup object wrong!", type: .error)
            return String()
        }
        
        mainGroupObjChildren.append(newUUID)
        mainGroupObj["children"] = JSON(mainGroupObjChildren)
        self._cacheProjet["objects"][self._mainGroupUUID] = mainGroupObj
        
        return newUUID
    }
    
    /// detection file type
    private func detectionType(path: String) -> String {
        if (path.isEmpty) {
            return "unknown"
        }
        
        let fileURL = URL(fileURLWithPath: path)
        
        let filePathExtension = fileURL.pathExtension
        if (!fileURL.isFileURL || filePathExtension.isEmpty) {
            return "unknown"
        }
        
        switch filePathExtension {
        case "a" :
            return "archive.ar"
        case "framework" :
            return "wrapper.framework"
        case "xib" :
            return "file.xib"
        case "plist" :
            return "text.plist.xml"
        case "bundle" :
            return "wrapper.plug-in"
        case "js" :
            return "sourcecode.javascript"
        case "html" :
            return "sourcecode.html"
        case "json" :
            return "sourcecode.json"
        case "xml" :
            return "sourcecode.xml"
        case "png" :
            return "image.png"
        case "txt" :
            return "text"
        case "xcconfig" :
            return "text.xcconfig"
        case "markdown" :
            return "text"
        case "tbd" :
            return "sourcecode.text-based-dylib-definition"
        case "sh" :
            return "text.script.sh"
        case "pch" :
            return "sourcecode.c.h"
        case "xcdatamodel" :
            return "wrapper.xcdatamodel"
        case "m" :
            return "sourcecode.c.objc"
        case "h" :
            return "sourcecode.c.h"
        case "swift" :
            return "sourcecode.swift"
        case "storyboard" :
            return "file.storyboard"
        case "dylib" :
            return "compiled.mach-o.dylib"
        case "jpg", "jpeg" :
            return "image.jpg"
        case "mp4" :
            return "video.mp4"
        case "app" :
            return "wrapper.application"
        case "xcassets" :
            return "folder.assetcatalog"
        default :
            return "unknown"
        }
    }
    
    
    /// Add framework to project
    ///
    /// - Parameter frameworkFilePath: framework path
    public mutating func linkFramework(_ frameworkFilePath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (frameworkFilePath.isEmpty || !FileManager.default.fileExists(atPath: frameworkFilePath)) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = "wrapper.framework"
        dict["sourceTree"] = "<group>"
        dict["name"] = frameworkFilePath.split(separator: "/").last ?? frameworkFilePath
        dict["path"] = frameworkFilePath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for object in objects {
            if (object.value == JSON(dict)) {
                xcodeManagerPrintLog("current object already exists.")
                return
            }
        }
        
        
        let PBXFileReferenceUUID = generateUUID()
        objects[PBXFileReferenceUUID] = JSON(dict)
        
        
        let PBXBuildFileUUID = generateUUID()
        var dict2 = Dictionary<String, Any>()
        dict2["fileRef"] = PBXFileReferenceUUID
        dict2["isa"] = "PBXBuildFile"
        dict["settings"] = ["ATTRIBUTES": ["Required"]] // Required OR Weak
        
        objects[PBXBuildFileUUID] = JSON(dict2)
        
        
        for object in objects {
            var obj = object.value.dictionaryObject ?? Dictionary()
            
            if (!obj.isEmpty && obj["isa"] as? String == "PBXFrameworksBuildPhase") {
                var files = obj["files"] as? Array<String> ?? Array()
                files.append(PBXBuildFileUUID)
                obj["files"] = files
                
                objects[object.key] = JSON(obj)
                
            }
        }
        
        self._cacheProjet["objects"] = JSON(objects)
        
        let newPath = frameworkFilePath.replacingOccurrences(of: frameworkFilePath.split(separator: "/").last ?? "", with: "")
        self.setFrameworkSearchPathValue(newPath)
    }
    
    
    /// Add static library to project
    ///
    /// - Parameter staticLibraryFilePath: static library file path
    public mutating func linkStaticLibrary(_ staticLibraryFilePath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (staticLibraryFilePath.isEmpty || !FileManager.default.fileExists(atPath: staticLibraryFilePath)) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = "archive.ar"
        dict["sourceTree"] = "<group>"
        dict["name"] = staticLibraryFilePath.split(separator: "/").last ?? staticLibraryFilePath
        dict["path"] = staticLibraryFilePath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for object in objects {
            if (object.value == JSON(dict)) {
                xcodeManagerPrintLog("current object already exists.")
                return
            }
        }
        
        let PBXFileReferenceUUID = generateUUID()
        objects[PBXFileReferenceUUID] = JSON(dict)
        
        let PBXBuildFileUUID = generateUUID()
        var dict2 = Dictionary<String, Any>()
        dict2["fileRef"] = PBXFileReferenceUUID
        dict2["isa"] = "PBXBuildFile"
        dict["settings"] = ["ATTRIBUTES": ["Required"]]  // Required OR Weak
        objects[PBXBuildFileUUID] = JSON(dict2)
        
        for object in objects {
            var obj = object.value.dictionaryObject ?? Dictionary()
            
            if (!obj.isEmpty && obj["isa"] as? String == "PBXFrameworksBuildPhase") {
                var files = obj["files"] as? Array<String> ?? Array()
                files.append(PBXBuildFileUUID)
                obj["files"] = files
                /// 写入缓存PBXFrameworksBuildPhase的缓存
                objects[object.key] = JSON(obj)
            }
        }
        self._cacheProjet["objects"] = JSON(objects)
        
        let newPath = staticLibraryFilePath.replacingOccurrences(of: staticLibraryFilePath.split(separator: "/").last ?? "", with: "")
        self.setLibrarySearchPathValue(newPath)
    }
    
    
    /// Remove a static library
    ///
    /// - Parameter staticLibraryFilePath: static library file path
    public mutating func unlinkStaticLibrary(_ staticLibraryFilePath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (staticLibraryFilePath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = "archive.ar"
        dict["sourceTree"] = "<group>"
        dict["name"] = staticLibraryFilePath.split(separator: "/").last ?? staticLibraryFilePath
        dict["path"] = staticLibraryFilePath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        var uuid = String()
        
        for (key, value) in objects {
            if (value == JSON(dict)) {
                
                if let _ = objects.removeValue(forKey: key) {
                    
                    uuid = key
                }
                break
            }
        }
        
        if (uuid.isEmpty) {
            xcodeManagerPrintLog("uuid is empty!", type: .error)
            return
        }
        
        // 检索"PBXFrameworksBuildPhase"
        for (key, value) in objects {
            var obj = value.dictionaryObject ?? Dictionary()
            if (obj.isEmpty) {
                continue
            }
            let isa = obj["isa"] as? String ?? String()
            if (isa.isEmpty) {
                continue
            }
            
            if (isa == "PBXBuildFile") {
                let fileRef = obj["fileRef"] as? String ?? String()
                if (fileRef == uuid) {
                    // 找到指针树,移除并回写
                    if let _ = objects.removeValue(forKey: key) {
                        self._cacheProjet["objects"] = JSON(objects)
                    }
                }
            }
            
            if (isa == "PBXFrameworksBuildPhase") {
                let fileUuids = obj["files"] as? Array<String> ?? Array()
                if (fileUuids.isEmpty) {
                    xcodeManagerPrintLog("`files` parse error!", type: .error)
                    continue
                }
                obj["files"] = fileUuids.filter{ $0 != uuid }
                // 移除完毕, 开始回写缓存
                objects[key] = JSON(obj)
                self._cacheProjet["objects"] = JSON(objects)
            }
        }
        
        /// !!! 注意:此处未删除LIBRARY_SEARCH_PATHS中的任何值,因为可能会有其他库文件在使用
        /// !!! LIBRARY_SEARCH_PATHS中即使没有库在使用留着也无关紧要
    }
    
    
    /// Remove framework to project
    ///
    /// - Parameter frameworkFilePath: framework path
    public mutating func unlinkFramework(_ frameworkFilePath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (frameworkFilePath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = "wrapper.framework"
        dict["sourceTree"] = "<group>"
        dict["name"] = frameworkFilePath.split(separator: "/").last ?? frameworkFilePath
        dict["path"] = frameworkFilePath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        var uuid = String()
        
        for (key, value) in objects {
            if (value == JSON(dict)) {
                
                if let _ = objects.removeValue(forKey: key) {
                    uuid = key
                }
                break
            }
        }
        
        if (uuid.isEmpty) {
            xcodeManagerPrintLog("uuid is empty!", type: .error)
            return
        }
        
        
        // 检索"PBXFrameworksBuildPhase"
        for (key, value) in objects {
            var obj = value.dictionaryObject ?? Dictionary()
            if (obj.isEmpty) {
                continue
            }
            let isa = obj["isa"] as? String ?? String()
            if (isa.isEmpty) {
                continue
            }
            if (isa == "PBXBuildFile") {
                let fileRef = obj["fileRef"] as? String ?? String()
                if (fileRef == uuid) {
                    // 找到指针树,移除并回写
                    if let _ = objects.removeValue(forKey: key) {
                        self._cacheProjet["objects"] = JSON(objects)
                    }
                }
            }
            
            if (isa == "PBXFrameworksBuildPhase") {
                let fileUuids = obj["files"] as? Array<String> ?? Array()
                if (fileUuids.isEmpty) {
                    xcodeManagerPrintLog("`files` parse error!", type: .error)
                    continue
                }
                
                obj["files"] = fileUuids.filter{ $0 != uuid }
                // 移除完毕, 开始回写缓存
                objects[key] = JSON(obj)
                self._cacheProjet["objects"] = JSON(objects)
            }
        }
        /// !!! 注意:此处未删除FRAMEWORK_SEARCH_PATHS中的任何值,因为可能会有其他库文件在使用
        /// !!! FRAMEWORK_SEARCH_PATHS中即使没有库在使用留着也无关紧要
    }
    
    /// Add folder to project
    ///
    /// - Parameter folderPath: folder path
    public mutating func addFolder(_ folderPath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (folderPath.isEmpty || !FileManager.default.fileExists(atPath: folderPath)) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let PBXFileReferenceUUID = generateUUID()
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = "folder"
        dict["sourceTree"] = "<group>"
        dict["name"] = folderPath.split(separator: "/").last ?? folderPath
        dict["path"] = folderPath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for object in objects {
            if (object.value == JSON(dict)) {
                xcodeManagerPrintLog("current object already exists.")
                return
            }
        }
        
        objects[PBXFileReferenceUUID] = JSON(dict)
        
        let PBXBuildFileUUID = generateUUID()
        var dict2 = Dictionary<String, Any>()
        dict2["fileRef"] = PBXFileReferenceUUID
        dict2["isa"] = "PBXBuildFile"
        objects[PBXBuildFileUUID] = JSON(dict2)
        
        for object in objects {
            var obj = object.value.dictionaryObject ?? Dictionary()
            
            if (!obj.isEmpty) {
                if obj["isa"] as? String == "PBXResourcesBuildPhase" {
                    var files = obj["files"] as? Array<String> ?? Array()
                    files.append(PBXBuildFileUUID)
                    obj["files"] = files
                    objects[object.key] = JSON(obj)
                }
            }
        }
        self._cacheProjet["objects"] = JSON(objects)
    }
    
    
    /// Add resources file to Project (Copy Bundle Rsources)
    ///
    /// - Parameter filePath: resources file
    public mutating func addFile(_ filePath: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (filePath.isEmpty || !FileManager.default.fileExists(atPath: filePath)) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let PBXFileReferenceUUID = generateUUID()
        var dict = Dictionary<String, Any>()
        dict["isa"] = "PBXFileReference"
        dict["lastKnownFileType"] = self.detectionType(path: filePath)
        dict["sourceTree"] = "<group>"
        dict["name"] = filePath.split(separator: "/").last ?? filePath
        dict["path"] = filePath
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for object in objects {
            if (object.value == JSON(dict)) {
                xcodeManagerPrintLog("current object already exists.")
                return
            }
        }
        
        objects[PBXFileReferenceUUID] = JSON(dict)
        
        let PBXBuildFileUUID = generateUUID()
        var dict2 = Dictionary<String, Any>()
        dict2["fileRef"] = PBXFileReferenceUUID
        dict2["isa"] = "PBXBuildFile"
        objects[PBXBuildFileUUID] = JSON(dict2)
        
        for object in objects {
            var obj = object.value.dictionaryObject ?? Dictionary()
            
            if (!obj.isEmpty) {
                if obj["isa"] as? String == "PBXResourcesBuildPhase" {
                    var files = obj["files"] as? Array<String> ?? Array()
                    files.append(PBXBuildFileUUID)
                    obj["files"] = files
                    objects[object.key] = JSON(obj)
                }
            }
        }
        self._cacheProjet["objects"] = JSON(objects)
    }
    
    
    /// Add FrameworkSearchPath Value
    ///
    /// - Parameter newPath: path
    public mutating func setFrameworkSearchPathValue(_ newPath: String) {
        
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (newPath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        objectsFor:
            for element in objects {
                var dict = element.value
                let isa = dict["isa"].string ?? String()
                if (isa == "XCBuildConfiguration") {
                    var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                    if (buildSettings.isEmpty) {
                        continue
                    }
                    
                    let PRODUCT_NAME = buildSettings["PRODUCT_NAME"]?.string ?? String()
                    let PRODUCT_BUNDLE_IDENTIFIER = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                    if (PRODUCT_NAME.isEmpty && PRODUCT_BUNDLE_IDENTIFIER.isEmpty) {
                        continue
                    }
                    
                    let FRAMEWORK_SEARCH_PATHS = buildSettings["FRAMEWORK_SEARCH_PATHS"]
                    let varType = FRAMEWORK_SEARCH_PATHS?.type ?? Type.unknown
                    switch varType {
                    case .string:
                        let string = FRAMEWORK_SEARCH_PATHS?.string ?? String()
                        if (newPath == string) {
                            xcodeManagerPrintLog("current object already exists.")
                            return
                        }
                        var newArray = Array<String>()
                        newArray.append(string)
                        newArray.append(newPath)
                        
                        // 回写
                        buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        break
                    case .array:
                        var newArray = FRAMEWORK_SEARCH_PATHS?.array ?? Array()
                        
                        for ele in newArray {
                            let str = ele.string ?? String()
                            if (str == newPath) {
                                break objectsFor
                            }
                        }
                        
                        newArray.append(JSON(newPath))
                        
                        buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        
                        break
                    default:
                        var newArray = Array<String>()
                        newArray.append("$(inherited)")
                        newArray.append(newPath)
                        
                        buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        
                        break
                    }
                }
        }
    }
    
    
    /// Add LibrarySearchPath Value
    ///
    /// - Parameter newPath: path
    public mutating func setLibrarySearchPathValue(_ newPath: String) {
        
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (newPath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        objectsFor:
            for element in objects {
                var dict = element.value
                let isa = dict["isa"].string ?? String()
                if (isa == "XCBuildConfiguration") {
                    var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                    if (buildSettings.isEmpty) {
                        continue
                    }
                    
                    let PRODUCT_NAME = buildSettings["PRODUCT_NAME"]?.string ?? String()
                    let PRODUCT_BUNDLE_IDENTIFIER = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                    if (PRODUCT_NAME.isEmpty && PRODUCT_BUNDLE_IDENTIFIER.isEmpty) {
                        continue
                    }
                    
                    let LIBRARY_SEARCH_PATHS = buildSettings["LIBRARY_SEARCH_PATHS"]
                    let varType = LIBRARY_SEARCH_PATHS?.type ?? Type.unknown
                    switch varType {
                    case .string:
                        let string = LIBRARY_SEARCH_PATHS?.string ?? String()
                        if (newPath == string) {
                            xcodeManagerPrintLog("current object already exists.")
                            return
                        }
                        var newArray = Array<String>()
                        newArray.append(string)
                        newArray.append(newPath)
                        
                        buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        break
                    case .array:
                        var newArray = LIBRARY_SEARCH_PATHS?.array ?? Array()
                        
                        for ele in newArray {
                            let str = ele.string ?? String()
                            if (str == newPath) {
                                break objectsFor
                            }
                        }
                        
                        newArray.append(JSON(newPath))
                        
                        buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        break
                    default:
                        var newArray = Array<String>()
                        newArray.append("$(inherited)")
                        newArray.append(newPath)
                        
                        buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                        break
                    }
                }
        }
    }
    
    /// Remove FrameworkSearchPath Value
    ///
    /// - Parameter removePath: path
    public mutating func removeFrameworkSearchPathValue(_ removePath: String) {
        
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (removePath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for element in objects {
            var dict = element.value
            let isa = dict["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                if (buildSettings.isEmpty) {
                    continue
                }
                
                let PRODUCT_NAME = buildSettings["PRODUCT_NAME"]?.string ?? String()
                let PRODUCT_BUNDLE_IDENTIFIER = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                if (PRODUCT_NAME.isEmpty && PRODUCT_BUNDLE_IDENTIFIER.isEmpty) {
                    continue
                }
                
                let FRAMEWORK_SEARCH_PATHS = buildSettings["FRAMEWORK_SEARCH_PATHS"]
                let varType = FRAMEWORK_SEARCH_PATHS?.type ?? Type.unknown
                switch varType {
                case .string:
                    let string = FRAMEWORK_SEARCH_PATHS?.string ?? String()
                    if (removePath == string) {
                        var newArray = Array<String>()
                        newArray.append("$(inherited)")
                        buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(newArray)
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                    }
                    break
                case .array:
                    let newArray = FRAMEWORK_SEARCH_PATHS?.array ?? Array()
                    let array = newArray.filter { $0.stringValue != removePath }
                    buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(array)
                    dict["buildSettings"] = JSON(buildSettings)
                    self._cacheProjet["objects"][element.key] = dict
                    break
                default:
                    var newArray = Array<String>()
                    newArray.append("$(inherited)")
                    buildSettings["FRAMEWORK_SEARCH_PATHS"] = JSON(newArray)
                    dict["buildSettings"] = JSON(buildSettings)
                    self._cacheProjet["objects"][element.key] = dict
                    break
                }
            }
        }
    }
    
    /// Remove LibrarySearchPath Value
    ///
    /// - Parameter removePath: path
    public mutating func removeLibrarySearchPathValue(_ removePath: String) {
        
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (removePath.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        if (objects.isEmpty) {
            xcodeManagerPrintLog("Parsed objects error!", type: .error)
            return
        }
        
        for element in objects {
            var dict = element.value
            let isa = dict["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                if (buildSettings.isEmpty) {
                    continue
                }
                
                let PRODUCT_NAME = buildSettings["PRODUCT_NAME"]?.string ?? String()
                let PRODUCT_BUNDLE_IDENTIFIER = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                if (PRODUCT_NAME.isEmpty && PRODUCT_BUNDLE_IDENTIFIER.isEmpty) {
                    continue
                }
                
                let LIBRARY_SEARCH_PATHS = buildSettings["LIBRARY_SEARCH_PATHS"]
                let varType = LIBRARY_SEARCH_PATHS?.type ?? Type.unknown
                switch varType {
                case .string:
                    let string = LIBRARY_SEARCH_PATHS?.string ?? String()
                    if (removePath == string) {
                        buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(["$(inherited)"])
                        dict["buildSettings"] = JSON(buildSettings)
                        self._cacheProjet["objects"][element.key] = dict
                    }
                    break
                case .array:
                    let newArray = LIBRARY_SEARCH_PATHS?.array ?? Array()
                    let array = newArray.filter { $0.stringValue != removePath }
                    buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(array)
                    dict["buildSettings"] = JSON(buildSettings)
                    self._cacheProjet["objects"][element.key] = dict
                    break
                default:
                    var newArray = Array<String>()
                    newArray.append("$(inherited)")
                    buildSettings["LIBRARY_SEARCH_PATHS"] = JSON(newArray)
                    dict["buildSettings"] = JSON(buildSettings)
                    self._cacheProjet["objects"][element.key] = dict
                    break
                }
            }
        }
    }
    
    /// Update Product Name
    ///
    /// - Parameter productName: productName
    public mutating func setProductName(_ productName: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (productName.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        for element in objects {
            var dict = element.value
            let isa = dict["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                let PRODUCT_NAME = buildSettings["PRODUCT_NAME"]?.string ?? String()
                if (!PRODUCT_NAME.isEmpty) {
                    buildSettings["PRODUCT_NAME"] = JSON(productName)
                    dict["buildSettings"] = JSON(buildSettings)
                    let uuidKey = element.key
                    
                    self._cacheProjet["objects"][uuidKey] = JSON(dict)
                }
            }
        }
    }
    
    /// Update project's bundleid
    ///
    /// - Parameter bundleid: bundleid, eg: cn.zhengshoudong.xxx
    public mutating func setBundleId(_ bundleid: String) {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use function 'init()' initialize!", type: .error)
            return
        }
        
        if (bundleid.isEmpty) {
            xcodeManagerPrintLog("Please check parameters!", type: .error)
            return
        }
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        for element in objects {
            var dict = element.value
            let isa = dict["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                let productBundleIdentifier = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                if (!productBundleIdentifier.isEmpty) {
                    buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = JSON(bundleid)
                    dict["buildSettings"] = JSON(buildSettings)
                    let uuidKey = element.key
                    
                    self._cacheProjet["objects"][uuidKey] = JSON(dict)
                }
            }
        }
    }
    
    /// Update project's codeSign style
    ///
    /// - Parameter type: enum CodeSignStyleType
    public mutating func setCodeSignStyle(type: CodeSignStyleType) {
        
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use the 'init()' initialize!", type: .error)
            return
        }
        
        var objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        for element in objects {
            var dict = element.value
            let isa = dict["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                var buildSettings = dict["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                let CODE_SIGN_STYLE = buildSettings["CODE_SIGN_STYLE"]?.string ?? String()
                if (!CODE_SIGN_STYLE.isEmpty) {
                    buildSettings["CODE_SIGN_STYLE"] = JSON(type.rawValue)
                    dict["buildSettings"] = JSON(buildSettings)
                    let uuidKey = element.key
                    objects[uuidKey] = JSON(dict)
                }
            }
        }
        
        let rootObj = objects[self._rootObjectUUID]?.dictionary ?? Dictionary<String, JSON>()
        var attributes = rootObj["attributes"]?.dictionary ?? Dictionary<String, JSON>()
        var targetAttributes = attributes["TargetAttributes"]?.dictionary ?? Dictionary<String, JSON>()
        var newTargetAttributes = Dictionary<String, JSON>()
        
        for attribute in targetAttributes {
            var singleAttribute = targetAttributes[attribute.key]?.dictionary ?? Dictionary<String, JSON>()
            for att in singleAttribute {
                if (att.key == "ProvisioningStyle") {
                    singleAttribute[att.key] = JSON(type.rawValue)
                    newTargetAttributes[attribute.key] = JSON(singleAttribute)
                }
            }
        }
        
        if (!newTargetAttributes.isEmpty) {
            objects[self._rootObjectUUID]!["attributes"]["TargetAttributes"] = JSON(newTargetAttributes)
        }
        
        self._cacheProjet["objects"] = JSON(objects)
    }
    
    /// Get project bundleid
    ///
    /// - Returns: return bundleid. (If has error, will return empty string.)
    public func getBundleId() -> String {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use the 'init()' initialize!", type: .error)
            return String()
        }
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        for (_, value) in objects {
            let isa = value["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                let buildSettings = value["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                let productBundleIdentifier = buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.string ?? String()
                if (!productBundleIdentifier.isEmpty) {
                    return productBundleIdentifier
                }
            }
        }
        return String()
    }
    
    /// Get product name
    ///
    /// - Returns: current product name.(If has error, will return empty string)
    public func getProductName() -> String {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use the 'init()' initialize!", type: .error)
            return String()
        }
        
        let objects = self._cacheProjet["objects"].dictionary ?? Dictionary()
        for (_, value) in objects {
            let isa = value["isa"].string ?? String()
            if (isa == "XCBuildConfiguration") {
                let buildSettings = value["buildSettings"].dictionary ?? Dictionary<String, JSON>()
                let productName = buildSettings["PRODUCT_NAME"]?.string ?? String()
                if (!productName.isEmpty) {
                    return productName
                }
            }
        }
        return String()
    }
    
    /// Save the project to file
    ///
    /// - Returns: Saved the result
    public func save() -> Bool {
        if (self._cacheProjet.isEmpty) {
            xcodeManagerPrintLog("Please use the 'init()' initialize!", type: .error)
            return false
        }
        
        let dict = _cacheProjet.dictionaryObject ?? Dictionary()
        if (dict.isEmpty) {
            xcodeManagerPrintLog("Save failed!", type: .error)
            return false
        }
        
        var fileUrl = URL(fileURLWithPath: _filePath)
        if fileUrl.pathExtension == "xcodeproj" {
            fileUrl.appendPathComponent("project.pbxproj")
        }
        
        return self.saveProject(fileURL: fileUrl, withPropertyList: dict)
    }
    
    private func xcodeManagerPrintLog<T>(_ message: T, type: XcodeManagerLogType = .info,
                                         file: String = #file, line: Int = #line, method: String = #function) {
        if (!self._isPrintLog) {
            return
        }
        
        let msg = message as? String ?? String()
        if (!msg.isEmpty) {
            print("[\(type.rawValue)] [\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(method): \(msg)")
        }
    }
    
}

extension Dictionary {
    fileprivate func isEqualTo(dict:[String: Any]) -> Bool {
        return NSDictionary(dictionary: self).isEqual(to: dict)
    }
}
