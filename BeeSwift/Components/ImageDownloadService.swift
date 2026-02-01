// Part of BeeSwift. Copyright Beeminder

import AlamofireImage

final class ImageDownloadService {
  static let shared = ImageDownloadService()
  let downloader: ImageDownloader

  private init() { downloader = ImageDownloader.default }
}
