import AVFoundation
import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var openingPhoto = false
    @State private var problem: Problem?

    private let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)

    private enum Problem {
        case cameraBlocked
        case photoUnreadable
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PlankArt()
                        .frame(height: 196)
                        .frame(maxWidth: .infinity)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.line))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Count scaffold planks")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Text("Photograph the plank ends, mark the stack, and get a numbered count. It runs on your phone, with no internet needed.")
                            .font(.body)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    tips
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)

            problemBanner
            Footer { actions }
        }
        .background(Palette.surface)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: problem)
        .fullScreenCover(isPresented: $showCamera, onDismiss: openCaptured) {
            CameraPicker { captured = $0 }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await open(item) }
        }
        .overlay {
            if openingPhoto {
                ZStack {
                    Palette.surface.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Opening photo").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppGlyph().frame(width: 30, height: 30)
            Text("Scaffold Count")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 0) {
            tip("camera.viewfinder", "Face the plank ends straight on")
            Divider().overlay(Palette.line).padding(.leading, 48)
            tip("rectangle.dashed", "Fit the whole stack in the photo")
            Divider().overlay(Palette.line).padding(.leading, 48)
            tip("sun.max", "Avoid strong glare on the ends")
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line))
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.primary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    @ViewBuilder private var actions: some View {
        if hasCamera {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("Library")
            }
            .buttonStyle(TextButtonStyle())
            .tourTarget("library")
            Button(action: takePhoto) {
                Label("Take photo", systemImage: "camera.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder private var problemBanner: some View {
        switch problem {
        case .cameraBlocked:
            Banner(
                systemName: "camera.badge.ellipsis",
                message: "Camera access is off for Scaffold Count.",
                actionTitle: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .padding(.bottom, 8)
        case .photoUnreadable:
            Banner(systemName: "exclamationmark.triangle", message: "Couldn't open that photo. Try another one.")
                .padding(.bottom, 8)
        case nil:
            EmptyView()
        }
    }

    private func takePhoto() {
        problem = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { showCamera = true } else { problem = .cameraBlocked }
                }
            }
        default:
            problem = .cameraBlocked
        }
    }

    private func openCaptured() {
        guard let image = captured else { return }
        captured = nil
        session.start(with: image)
    }

    private func open(_ item: PhotosPickerItem) async {
        problem = nil
        withAnimation { openingPhoto = true }
        defer {
            pickerItem = nil
            withAnimation { openingPhoto = false }
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            problem = .photoUnreadable
            return
        }
        session.start(with: image)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
