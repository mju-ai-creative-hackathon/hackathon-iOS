import SwiftUI
import PhotosUI
import UIKit

/// 스팟 미션 시트: 촬영 -> 도장 쾅
struct SpotMissionView: View {
    let courseID: UUID
    let spotID: UUID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var stampDone = false
    @State private var stampScale: CGFloat = 2.2
    @State private var stampAngle: Double = -40
    @State private var stampOpacity: Double = 0

    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    private var spot: TourSpot? {
        store.course(courseID)?.spots.first { $0.id == spotID }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let spot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(spot.name).font(Theme.title(26)).foregroundStyle(Theme.blueDeep)

                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                            Text("위치 확인됨 · 약 \(distanceText(spot))")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.blue.opacity(0.12)))
                        .foregroundStyle(Theme.blue)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("오늘의 미션").font(Theme.hand(16)).foregroundStyle(Theme.red)
                            Text("📸 \(spot.mission)").font(Theme.hand(20)).foregroundStyle(Theme.blueDeep)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paperCard()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("예시 구도").font(Theme.hand(15)).foregroundStyle(Theme.blue)
                            AsyncImage(url: spot.previewURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Rectangle().fill(Theme.blueSoft.opacity(0.4))
                                }
                            }
                            .frame(height: 200).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if let photo = spot.capturedPhoto {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("내가 찍은 사진").font(Theme.hand(15)).foregroundStyle(Theme.blue)
                                Image(uiImage: photo).resizable().scaledToFill()
                                    .frame(height: 140).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }

                        actionArea(spot)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollDisabled(stampDone)
            }

            if stampDone { stampOverlay }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onPick: { img in showCamera = false; completeStamp(img) },
                         onCancel: { showCamera = false })
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    completeStamp(img)
                }
                pickerItem = nil
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func actionArea(_ spot: TourSpot) -> some View {
        let retake = spot.isStamped
        if cameraAvailable {
            Button { showCamera = true } label: {
                Text(retake ? "다시 찍기" : "카메라로 찍기")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            VStack(spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(retake ? "사진 다시 고르기" : "앨범에서 사진 고르기")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("이 기기에는 카메라가 없어서 앨범으로 대신해요")
                    .font(Theme.hand(14)).foregroundStyle(Theme.blue)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var stampOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                StampMark(color: Theme.red, size: 190)
                    .scaleEffect(stampScale)
                    .rotationEffect(.degrees(stampAngle))
                    .opacity(stampOpacity)
                Text("도장 쾅!").font(Theme.hand(26)).foregroundStyle(Theme.paper)
                    .opacity(stampOpacity)
            }
        }
        .transition(.opacity)
    }

    private func distanceText(_ spot: TourSpot) -> String {
        let seed = abs(spot.name.hashValue % 40)
        return "\(10 + seed)m"
    }

    private func completeStamp(_ image: UIImage) {
        store.stamp(courseID: courseID, spotID: spotID, photo: image)
        stampScale = 2.2; stampAngle = -40; stampOpacity = 0
        withAnimation(.easeOut(duration: 0.15)) { stampDone = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
            stampScale = 1; stampAngle = 0; stampOpacity = 1
        }
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            dismiss()
        }
    }
}
