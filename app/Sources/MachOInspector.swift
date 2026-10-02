import Foundation
import MachO
import Security

public enum MachOInspector {
    public static func inspect(atPath path: String) -> DylibInspectionResult? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return inspect(url: url)
    }
    
    public static func inspect(url: URL) -> DylibInspectionResult? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 8 else {
            return nil
        }
        
        let totalFileSize = UInt64(data.count)
        let fileName = url.lastPathComponent
        
        return data.withUnsafeBytes { rawBuffer -> DylibInspectionResult? in
            guard let basePtr = rawBuffer.baseAddress else { return nil }
            
            let magic = basePtr.load(as: UInt32.self)
            var slices: [DylibSliceInfo] = []
            var primarySliceOffset: UInt64 = 0
            
            // Check Fat Universal Binary
            if magic == FAT_MAGIC || magic == FAT_CIGAM {
                let nfat = NSSwapBigIntToHost(basePtr.advanced(by: 4).load(as: UInt32.self))
                var archPtr = basePtr.advanced(by: 8)
                let headerEnd = basePtr.advanced(by: rawBuffer.count)
                
                for _ in 0..<nfat {
                    guard archPtr.advanced(by: MemoryLayout<fat_arch>.size) <= headerEnd else { break }
                    let cputype = NSSwapBigIntToHost(archPtr.load(as: UInt32.self))
                    let offset = NSSwapBigIntToHost(archPtr.advanced(by: 8).load(as: UInt32.self))
                    let size = NSSwapBigIntToHost(archPtr.advanced(by: 12).load(as: UInt32.self))
                    
                    let arch: CpuArch
                    if cputype == CPU_TYPE_ARM64 {
                        arch = .arm64
                    } else if cputype == CPU_TYPE_X86_64 {
                        arch = .x86_64
                    } else {
                        arch = .unknown
                    }
                    
                    slices.append(DylibSliceInfo(arch: arch, fileOffset: UInt64(offset), sliceSize: UInt64(size)))
                    
                    #if arch(arm64)
                    if cputype == CPU_TYPE_ARM64 { primarySliceOffset = UInt64(offset) }
                    #else
                    if cputype == CPU_TYPE_X86_64 { primarySliceOffset = UInt64(offset) }
                    #endif
                    
                    archPtr = archPtr.advanced(by: MemoryLayout<fat_arch>.size)
                }
                
                if primarySliceOffset == 0, let firstSlice = slices.first {
                    primarySliceOffset = firstSlice.fileOffset
                }
            } else if magic == MH_MAGIC_64 || magic == MH_CIGAM_64 {
                let cputype = basePtr.advanced(by: 4).load(as: UInt32.self)
                let arch: CpuArch = (cputype == CPU_TYPE_ARM64) ? .arm64 : (cputype == CPU_TYPE_X86_64 ? .x86_64 : .unknown)
                slices.append(DylibSliceInfo(arch: arch, fileOffset: 0, sliceSize: totalFileSize))
                primarySliceOffset = 0
            } else if magic == MH_MAGIC || magic == MH_CIGAM {
                slices.append(DylibSliceInfo(arch: .unknown, fileOffset: 0, sliceSize: totalFileSize))
                primarySliceOffset = 0
            } else {
                // Not a recognized Mach-O or Universal binary
                return nil
            }
            
            // Parse load commands from primary slice
            guard Int(primarySliceOffset) + MemoryLayout<mach_header_64>.size <= rawBuffer.count else {
                return DylibInspectionResult(
                    filePath: url.path,
                    fileName: fileName,
                    installName: fileName,
                    currentVersion: "1.0.0",
                    compatibilityVersion: "1.0.0",
                    slices: slices,
                    dependencies: [],
                    rpaths: [],
                    isSigned: false,
                    isAdHoc: false,
                    teamIdentifier: nil,
                    totalFileSize: totalFileSize
                )
            }
            
            let slicePtr = basePtr.advanced(by: Int(primarySliceOffset))
            let sliceMagic = slicePtr.load(as: UInt32.self)
            let is64 = (sliceMagic == MH_MAGIC_64 || sliceMagic == MH_CIGAM_64)
            let headerSize = is64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
            
            let ncmds = slicePtr.advanced(by: 16).load(as: UInt32.self)
            var cmdPtr = slicePtr.advanced(by: headerSize)
            let sliceEnd = slicePtr.advanced(by: Int(slices.first(where: { $0.fileOffset == primarySliceOffset })?.sliceSize ?? UInt64(rawBuffer.count - Int(primarySliceOffset))))
            
            var installName = fileName
            var curVersion = "1.0.0"
            var compatVersion = "1.0.0"
            var dependencies: [String] = []
            var rpaths: [String] = []
            var isSigned = false
            
            for _ in 0..<ncmds {
                guard cmdPtr.advanced(by: 8) <= sliceEnd else { break }
                let cmd = cmdPtr.load(as: UInt32.self)
                let cmdsize = cmdPtr.advanced(by: 4).load(as: UInt32.self)
                guard cmdsize >= 8, cmdPtr.advanced(by: Int(cmdsize)) <= sliceEnd else { break }
                
                if cmd == LC_ID_DYLIB {
                    let nameOffset = cmdPtr.advanced(by: 8).load(as: UInt32.self)
                    let curVerNum = cmdPtr.advanced(by: 16).load(as: UInt32.self)
                    let compatVerNum = cmdPtr.advanced(by: 20).load(as: UInt32.self)
                    
                    curVersion = formatVersion(curVerNum)
                    compatVersion = formatVersion(compatVerNum)
                    
                    if Int(nameOffset) < Int(cmdsize) {
                        let cStr = cmdPtr.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self)
                        let parsedName = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !parsedName.isEmpty {
                            installName = parsedName
                        }
                    }
                } else if cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == 0x1f /* LC_REEXPORT_DYLIB */ {
                    let nameOffset = cmdPtr.advanced(by: 8).load(as: UInt32.self)
                    if Int(nameOffset) < Int(cmdsize) {
                        let cStr = cmdPtr.advanced(by: Int(nameOffset)).assumingMemoryBound(to: CChar.self)
                        let dep = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !dep.isEmpty && !dependencies.contains(dep) {
                            dependencies.append(dep)
                        }
                    }
                } else if cmd == LC_RPATH {
                    let pathOffset = cmdPtr.advanced(by: 8).load(as: UInt32.self)
                    if Int(pathOffset) < Int(cmdsize) {
                        let cStr = cmdPtr.advanced(by: Int(pathOffset)).assumingMemoryBound(to: CChar.self)
                        let rp = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rp.isEmpty && !rpaths.contains(rp) {
                            rpaths.append(rp)
                        }
                    }
                } else if cmd == LC_CODE_SIGNATURE {
                    isSigned = true
                }
                
                cmdPtr = cmdPtr.advanced(by: Int(cmdsize))
            }
            
            // Check code signing metadata via Security framework
            var teamId: String? = nil
            var isAdHoc = false
            
            var staticCode: SecStaticCode?
            if SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
               let sc = staticCode {
                var infoRef: CFDictionary?
                if SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
                   let info = infoRef as? [String: Any] {
                    isSigned = true
                    if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
                        teamId = team
                    }
                    if let flags = info[kSecCodeInfoFlags as String] as? UInt32 {
                        // CS_ADHOC = 0x2
                        isAdHoc = (flags & 0x00000002) != 0
                    }
                }
            }
            
            return DylibInspectionResult(
                filePath: url.path,
                fileName: fileName,
                installName: installName,
                currentVersion: curVersion,
                compatibilityVersion: compatVersion,
                slices: slices,
                dependencies: dependencies,
                rpaths: rpaths,
                isSigned: isSigned,
                isAdHoc: isAdHoc,
                teamIdentifier: teamId,
                totalFileSize: totalFileSize
            )
        }
    }
    
    private static func formatVersion(_ ver: UInt32) -> String {
        let major = (ver >> 16) & 0xFFFF
        let minor = (ver >> 8) & 0xFF
        let patch = ver & 0xFF
        return "\(major).\(minor).\(patch)"
    }
}
