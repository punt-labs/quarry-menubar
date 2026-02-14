import Foundation

// MARK: - HealthResponse

struct HealthResponse: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case status
        case uptimeSeconds = "uptime_seconds"
    }

    let status: String
    let uptimeSeconds: Double

}

// MARK: - SearchResponse

struct SearchResponse: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case query
        case totalResults = "total_results"
        case results
    }

    let query: String
    let totalResults: Int
    let results: [SearchResult]

}

// MARK: - SearchResult

struct SearchResult: Codable, Sendable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case documentName = "document_name"
        case collection
        case pageNumber = "page_number"
        case chunkIndex = "chunk_index"
        case text
        case pageType = "page_type"
        case sourceFormat = "source_format"
        case similarity
    }

    let documentName: String
    let collection: String
    let pageNumber: Int
    let chunkIndex: Int
    let text: String
    let pageType: String
    let sourceFormat: String
    let similarity: Double

    var id: String {
        "\(documentName)-\(pageNumber)-\(chunkIndex)"
    }

}

// MARK: - DocumentsResponse

struct DocumentsResponse: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case totalDocuments = "total_documents"
        case documents
    }

    let totalDocuments: Int
    let documents: [DocumentInfo]

}

// MARK: - DocumentInfo

struct DocumentInfo: Codable, Sendable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case documentName = "document_name"
        case documentPath = "document_path"
        case collection
        case totalPages = "total_pages"
        case chunkCount = "chunk_count"
        case indexedPages = "indexed_pages"
        case ingestionTimestamp = "ingestion_timestamp"
    }

    let documentName: String
    let documentPath: String
    let collection: String
    let totalPages: Int
    let chunkCount: Int
    let indexedPages: Int
    let ingestionTimestamp: String

    var id: String {
        "\(collection)/\(documentName)"
    }

}

// MARK: - CollectionsResponse

struct CollectionsResponse: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case totalCollections = "total_collections"
        case collections
    }

    let totalCollections: Int
    let collections: [CollectionInfo]

}

// MARK: - CollectionInfo

struct CollectionInfo: Codable, Sendable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case collection
        case documentCount = "document_count"
        case chunkCount = "chunk_count"
    }

    let collection: String
    let documentCount: Int
    let chunkCount: Int

    var id: String {
        collection
    }

}

// MARK: - StatusResponse

struct StatusResponse: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case documentCount = "document_count"
        case collectionCount = "collection_count"
        case chunkCount = "chunk_count"
        case databasePath = "database_path"
        case databaseSizeBytes = "database_size_bytes"
        case embeddingModel = "embedding_model"
        case embeddingDimension = "embedding_dimension"
    }

    let documentCount: Int
    let collectionCount: Int
    let chunkCount: Int
    let databasePath: String
    let databaseSizeBytes: Int
    let embeddingModel: String
    let embeddingDimension: Int

}

// MARK: - ErrorResponse

struct ErrorResponse: Codable, Sendable {
    let error: String
}
