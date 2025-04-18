
import SwiftUI

struct RecordItem : Identifiable {
	let id: UUID
	let name: String
	let date: Date
	let fileURL: URL
	
	var formattedDate: String {
		let formatter = DateFormatter()
		formatter.locale = Locale.current
		formatter.dateStyle = .full
		formatter.timeStyle = .full
		return formatter.string(from: date)
	}
}

func recordDir() -> URL {
	return FileManager.default.urls(
		for: .documentDirectory,
		in: .userDomainMask
	).first!.appendingPathComponent("records", conformingTo: .directory)
}

func loadRecordInfoFromFile(fileURL: URL) throws -> RecordItem
{
	let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
	let date = attrs[.creationDate] as! Date
	
	return RecordItem(
		id:UUID(),
		name: fileURL.deletingPathExtension().lastPathComponent,
		date: date,
		fileURL: fileURL
	)
}

func loadRecordItems() -> [RecordItem] {
	guard let files = try? FileManager.default.contentsOfDirectory(at: recordDir(), includingPropertiesForKeys: nil) else {
		return []
	}
	var records = [RecordItem]()
	for file in files {
		do {
			records.append(try loadRecordInfoFromFile(fileURL: file))
		}
		catch {}
	}
	return records
}

struct ContentView: View {
	@ObservedObject var pipelineController: AudioPipelineController
	@State var recordItems = loadRecordItems()
	@State var expandedRecord = UUID()
	@State var isRenaming = false
	@State var renamingFileName: String = ""
	@State var renamingFileID = UUID()
	
    var body: some View {
		VStack(spacing: 0) {
			HStack
			{
				Text("Audio Effects SDK demo").font(.title2).padding(.leading).padding(.bottom).frame(alignment: .leading)
				Spacer()
			}
			Divider().frame(height: 1).frame(alignment: .top)
			Group {
				if (isRenaming) {
					RenameFileView(name: $renamingFileName, onCancel: {
						isRenaming = false
					}, onApply: {
						isRenaming = !renameRecordFile(id: renamingFileID, newName: renamingFileName)
					}).frame(maxWidth: .infinity, maxHeight: .infinity)
				}
				else if (pipelineController.state == .ready) {
					mainView
				}
				else if(pipelineController.state == .uninitialized) {
					initialView
				}
				else {
					loadingView
				}
			}
		}.alert("Microphone Permission Denied", isPresented:Binding (
			get: { pipelineController.errorStatus != .noErr }, set: { _,_ in pipelineController.resetErrorStatus() }
		)) {
			Button("Open Settings") {
				UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
			}
			Button("Ok", role: .cancel) {}
		}
	}
	
	func playlistItemContent(_ item: RecordItem) -> some View {
		HStack {
			VStack(alignment: .leading) {
				Text(item.name).font(.title3)
				Text(item.formattedDate).font(.caption2)
			}.padding(.horizontal).padding(.bottom)
			Spacer()
			Menu {
				Button {
					try? FileManager.default.removeItem(at: item.fileURL)
					recordItems.removeAll(where: { i in
						i.id == item.id
					})
				} label: {
					Text("Remove")
				}
				Button {
					renamingFileID = item.id
					renamingFileName = item.name
					isRenaming = true
				} label: {
					Text("Rename")
				}
			} label: {
				Image(systemName:"line.3.horizontal")
					.resizable()
					.frame(width: 20, height: 16)
					.padding()
					.background(Color.clear)
					.contentShape(Rectangle())
			}.buttonStyle(.plain)
		}
	}
	
	func playlistItemButtonContent(isPlaying: Bool, name: String) -> some View {
		VStack {
			Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
				.imageScale(.large)
			Text(isPlaying ? "STOP" : name)
		}
	}
	
	var playList: some View {
		List(recordItems) { item in
			Group {
				if (expandedRecord == item.id) {
					VStack{
						playlistItemContent(item)
							.contentShape(Rectangle())
						HStack {
							Button {
								onPlayButton(fileURL: item.fileURL, withFilter: false)
							} label: {
								playlistItemButtonContent(isPlaying: isFilePlaying(fileURL: item.fileURL) && !pipelineController.playingWithFilter, name: "ORIGINAL")
							}.buttonStyle(PlainButtonStyle())
							Button {
								onPlayButton(fileURL: item.fileURL, withFilter: true)
							} label: {
								playlistItemButtonContent(isPlaying: isFilePlaying(fileURL: item.fileURL) && pipelineController.playingWithFilter, name: "DENOISE")
							}.buttonStyle(PlainButtonStyle())
						}
					}
				}
				else {
					Button {
						expandedRecord = item.id
					} label: {
						playlistItemContent(item)
					}
				}
			}.listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
		}.listStyle(PlainListStyle())
	}
	
	var rocordButtonContent: some View {
		Circle().overlay {
			Group {
				if (pipelineController.recordingState == .performing) {
					Text(currentRecordTimeStr)
				}
				else if (pipelineController.recordingState == .starting) {
					Text("STARTING")
				}
				else if (pipelineController.recordingState == .stopping) {
					Text("STOPPING")
				}
				else {
					Text("START MIC CAPTURING")
				}
			}.foregroundStyle(.white).font(.system(size: 20))
		}.shadow(color:Color.black.opacity(0.55), radius: 3)
	}
	
	var mainView: some View {
		VStack {
			playList.padding(.bottom)
			HStack {
				Spacer()
				Button(action: onRecordButton, label: {
					rocordButtonContent.frame(width: 140)
				}).padding(.trailing, 20).padding(.bottom, 30).disabled(
					pipelineController.mode != .idle && pipelineController.mode != .recording
				)
			}
			Toggle(isOn: $pipelineController.playback) {
				HStack {
					Text("Enable playback")
				}
			}.padding(.horizontal)
			Toggle(isOn: $pipelineController.playbackNoiseSupression) {
				HStack {
					Text("Enable noise supression for playback")
				}
			}.padding(.horizontal)
		}
	}
	
	var initialView: some View {
		Button(action: { Task {
			await pipelineController.initialize()
		}}, label: {
			Circle().overlay {
				Text("Retry").foregroundStyle(.white).font(.system(size: 40))
			}.padding()
		}).frame(maxWidth: .infinity, maxHeight: .infinity)
	}
	
	var loadingView: some View {
		VStack {
			ProgressView()
				.progressViewStyle(CircularProgressViewStyle(tint: .blue))
				.controlSize(.large)
				.scaleEffect(3)
			Text(convertState(pipelineController.state))
				.padding(.top, 38)
				.foregroundColor(.gray)
				.font(.system(size: 26))
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
	
	var currentRecordTimeStr: String {
		String(format: "%02d:%02d:%02d",
			   pipelineController.recordedSecondCount / (60 * 60),
			   (pipelineController.recordedSecondCount / 60) % 60,
			   pipelineController.recordedSecondCount % 60
		)
	}
	
	func onRecordButton()
	{
		Task {
			if (pipelineController.recordingState == .inactive) {
				await pipelineController.startRecording()
				return
			}
			
			guard let recordedFileURL = await pipelineController.stopRecording() else {
				return
			}
			
			if !FileManager.default.fileExists(atPath: recordDir().path) {
				try? FileManager.default.createDirectory(atPath: recordDir().path, withIntermediateDirectories: true, attributes: nil)
			}
			
			var index = 0
			let date = Date.now
			while FileManager.default.fileExists(atPath: fullFileURL(date: date, index: index).path) {
				index += 1
			}
			let dstFileURL = fullFileURL(date: date, index: index)
			do {
				try FileManager.default.moveItem(at: recordedFileURL, to: dstFileURL)
				let newItem = try loadRecordInfoFromFile(fileURL: dstFileURL)
				await MainActor.run {
					self.recordItems.append(newItem)
				}
			}
			catch {	}
		}
	}
	
	func buildFileName(date: Date, index: Int) -> String {
		let dateStr = date.formatted(date: .omitted, time: .standard)
		let baseName = String(format: "Test record %@", dateStr)
		return index > 0 ? String(format: "%@ (%d)", baseName, index) : baseName
	}
	
	func fullFileURL(date: Date, index: Int) -> URL {
		let fileName = buildFileName(date: date, index: index)
		return recordDir().appendingPathComponent(fileName, conformingTo: .wav)
	}
	
	func isFilePlaying(fileURL: URL) -> Bool {
		fileURL == pipelineController.playingFileURL &&
		pipelineController.playingState != .inactive &&
		pipelineController.playingState != .stopping
	}
	
	func onPlayButton(fileURL: URL, withFilter: Bool) {
		Task {
			let playNext = 
				fileURL != pipelineController.playingFileURL ||
				pipelineController.playingState == .inactive ||
				pipelineController.playingWithFilter != withFilter
			
			await pipelineController.stopPlaying()
			
			if playNext {
				await pipelineController.startPlaying(fileURL: fileURL, withFilter: withFilter)
			}
		}
	}
	
	func renameRecordFile(id: UUID, newName: String) -> Bool {
		guard let recordIndex = recordItems.firstIndex(where: { i in
			i.id == id
		}) else {
			return false
		}
		let prevRecord = recordItems[recordIndex]
		let recordDir = prevRecord.fileURL.deletingLastPathComponent()
		let newFileURL = recordDir
			.appendingPathComponent(newName)
			.appendingPathExtension(prevRecord.fileURL.pathExtension)
		
		guard !FileManager.default.fileExists(atPath: newFileURL.path) else {
			return false
		}
		
		do {
			try FileManager.default.moveItem(at: prevRecord.fileURL, to: newFileURL)
		}
		catch {
			return false
		}
		
		let newRecord = RecordItem(
			id: prevRecord.id,
			name: newName,
			date: prevRecord.date,
			fileURL: newFileURL
		)
		recordItems[recordIndex] = newRecord
		
		return true
	}
	
	func convertState(_ state: PipelineState) -> String {
		if (state == .authorization) {
			return "Authorization..."
		}
		return "Initialization..."
	}
}

#Preview {
	ContentView(pipelineController: AudioPipelineController(), recordItems: [
		RecordItem(id: UUID(), name: "Test name 1", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav")),
		RecordItem(id: UUID(), name: "Test name 2", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav")),
		RecordItem(id: UUID(), name: "Test name 3", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav"))
	])
}
