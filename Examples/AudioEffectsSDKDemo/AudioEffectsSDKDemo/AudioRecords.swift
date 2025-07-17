import AVFoundation

struct RecordItem : Identifiable {
	let id: UUID
	let name: String
	let date: Date
	let fileURL: URL
	let sampleRate: Int
	
	var formattedDate: String {
		let formatter = DateFormatter()
		formatter.locale = Locale.current
		formatter.dateStyle = .full
		formatter.timeStyle = .full
		return formatter.string(from: date)
	}
}

func loadSampleRate(file: URL) async -> Int {
	let asset = AVURLAsset(url: file)
	let tracks = try? await asset.loadTracks(withMediaType: .audio)
	let formatDesc: [CMFormatDescription]? = try? await tracks?.first?.load(.formatDescriptions)
	let result = formatDesc?.first?.audioStreamBasicDescription?.mSampleRate ?? 0
	return Int(result)
}

func recordDir() -> URL {
	return FileManager.default.urls(
		for: .documentDirectory,
		in: .userDomainMask
	).first!.appendingPathComponent("records", conformingTo: .directory)
}

func loadRecordInfoFromFile(fileURL: URL) async throws -> RecordItem
{
	let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
	let date = attrs[.creationDate] as! Date
	let sampleRate = await loadSampleRate(file: fileURL)
	
	return RecordItem(
		id:UUID(),
		name: fileURL.deletingPathExtension().lastPathComponent,
		date: date,
		fileURL: fileURL,
		sampleRate: sampleRate
	)
}

func enumerateRecodFiles() -> [URL] {
	/// This is example.  Replace file names by names of files that you want to bundle with the app
	let builtInNames = ["custom-sample-1", "custom-sample-2"]
	
	var files = [URL]()
	for name in builtInNames {
		let path = Bundle.main.path(forResource: name, ofType: "mp3")
		if let path {
			files.append(URL(fileURLWithPath: path))
		}
	}
	
	let recordedFiles = try? FileManager.default.contentsOfDirectory(
		at: recordDir(),
		includingPropertiesForKeys: nil
	)
	guard let recordedFiles else {
		return files
	}
	files.append(contentsOf: recordedFiles)
	return files
}

func loadRecordItems() async -> [RecordItem] {
	let files = enumerateRecodFiles()
	var records = [RecordItem]()
	for file in files {
		do {
			records.append(try await loadRecordInfoFromFile(fileURL: file))
		}
		catch {}
	}
	return records
}
