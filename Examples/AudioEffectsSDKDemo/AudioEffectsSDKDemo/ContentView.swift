
import SwiftUI

func findCurrentUIWindow() -> UIWindow? {
	let connectedScenes = UIApplication.shared.connectedScenes
		.filter { scene in scene.activationState == .foregroundActive }
		.compactMap { scene in scene as? UIWindowScene }
	
	let window = connectedScenes.first?
		.windows
		.first { window in window.isKeyWindow }
	return window
}

struct ContentView: View {
	@ObservedObject var pipelineController: AudioPipelineController
	@ObservedObject var records: Records
	@State var expandedRecord = UUID()
	@State var isRenaming = false
	@State var renamingFileName: String = ""
	@State var renamingFileID = UUID()
	@State var sampleRate = 48000
	@State var audioFormat: AudioSampleFormat = .pcmInt16
	
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
				Text(String(format: "[%@] %@", sampleRateName(item.sampleRate), item.name)).font(.title3)
				Text(item.formattedDate).font(.caption2)
			}.padding(.horizontal).padding(.bottom)
			Spacer()
			Menu {
				Button {
					try? FileManager.default.removeItem(at: item.fileURL)
					records.items.removeAll(where: { i in
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
				Button {
					guard let vc = findCurrentUIWindow()?.rootViewController else {
						return
					}
					let av = UIActivityViewController(activityItems: [item.fileURL], applicationActivities: nil)
					if let popover = av.popoverPresentationController {
						 popover.sourceView = vc.view
						 popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
						 popover.permittedArrowDirections = []
					 }
					vc.present(av, animated: true)
				} label: {
					Text("Share")
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
		List(records.items) { item in
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
						}.disabled(pipelineController.playingState == .starting)
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
				formatPicker.padding(.leading, 20)
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
		let sampleRate = self.sampleRate
		Task {
			if (pipelineController.recordingState == .inactive) {
				await pipelineController.startRecording(sampleRate: sampleRate, format: audioFormat)
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
				let newItem = try await loadRecordInfoFromFile(fileURL: dstFileURL)
				await MainActor.run {
					self.records.items.append(newItem)
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
		let filterOnly =
			withFilter != pipelineController.playingWithFilter &&
			pipelineController.mode == .playing &&
			fileURL == pipelineController.playingFileURL
		
		if (filterOnly) {
			pipelineController.playingWithFilter = withFilter
			return
		}
		
		let playNext = fileURL != pipelineController.playingFileURL
		
		Task {
			await pipelineController.stopPlaying()
			
			if playNext {
				await pipelineController.startPlaying(fileURL: fileURL, format: audioFormat)
			}
		}
		pipelineController.playingWithFilter = withFilter
	}
	
	func renameRecordFile(id: UUID, newName: String) -> Bool {
		guard let recordIndex = records.items.firstIndex(where: { i in
			i.id == id
		}) else {
			return false
		}
		let prevRecord = records.items[recordIndex]
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
			fileURL: newFileURL,
			sampleRate: prevRecord.sampleRate
		)
		records.items[recordIndex] = newRecord
		
		return true
	}
	
	var formatPicker: some View {
		HStack (spacing: 2) {
				Button {
					let currentIndex = sampleRates.firstIndex(of: sampleRate)!
					let nextIndex = (currentIndex + 1) % sampleRates.count
					sampleRate = sampleRates[nextIndex]
				} label: {
					Text(sampleRateName(presentedSampleRate))
						.frame(minWidth: 65, minHeight: 45)
				}
				Button {
					let currentIndex = AudioSampleFormat.allCases.firstIndex(of: audioFormat)!
					let nextIndex = (currentIndex + 1) % AudioSampleFormat.allCases.count
					audioFormat = AudioSampleFormat.allCases[nextIndex]
				} label: {
					Text(audioFormatName(presentedAudioFormat))
						.frame(minWidth: 65, minHeight: 45)
				}
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.automatic)
		.disabled(pipelineController.mode != .idle)
	}
	
	func sampleRateName(_ rate: Int) -> String {
		let khz = rate / 1000
		let sub = (rate % 1000) / 100
		if sub > 0 {
			return "\(khz).\(sub)kHz"
		}
		return "\(khz)kHz"
	}
	
	func audioFormatName(_ format: AudioSampleFormat) -> String {
		switch(format) {
		case .pcmInt16:
			return "Int 16"
		case .pcmFloat32:
			return "Float 32"
		case .pcmFloat32WebRTC:
			return "Float 32 WebRTC"
		}
	}
	
	var presentedSampleRate: Int {
		switch (pipelineController.mode) {
		case .idle:
			return self.sampleRate
		case .playing:
			return pipelineController.playingSampleRate
		case .recording:
			return pipelineController.recordingSampleRate
		}
	}
	
	var presentedAudioFormat: AudioSampleFormat {
		switch (pipelineController.mode) {
		case .idle:
			return self.audioFormat
		case .playing:
			return pipelineController.playingFormat
		case .recording:
			return pipelineController.recordingFormat
		}
	}
	
	func convertState(_ state: PipelineState) -> String {
		if (state == .authorization) {
			return "Authorization..."
		}
		return "Initialization..."
	}
	
	var sampleRates: [Int] {
		return [16000, 24000, 32000, 44100, 48000]
	}
}

#Preview {
	ContentView(pipelineController: AudioPipelineController(), records: Records([
		RecordItem(id: UUID(), name: "Test name 1", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav"), sampleRate: 44100),
		RecordItem(id: UUID(), name: "Test name 2", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav"), sampleRate: 32000),
		RecordItem(id: UUID(), name: "Test name 3", date: Date.now, fileURL: URL(fileURLWithPath: "./stub.wav"), sampleRate: 48000)
	]))
}
