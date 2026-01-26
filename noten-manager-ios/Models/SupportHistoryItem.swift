import Foundation

enum SupportHistoryItem: Identifiable, Hashable {
    case ticket(SupportTicket)
    case accessRequest(SupportAccessRequest)
    
    var id: String {
        switch self {
        case .ticket(let ticket): return "ticket_\(ticket.id)"
        case .accessRequest(let request): return "access_\(request.id)"
        }
    }
    
    var createdAt: Date {
        switch self {
        case .ticket(let ticket): return ticket.createdAt
        case .accessRequest(let request): return request.createdAt
        }
    }
    
    var title: String {
        switch self {
        case .ticket(let ticket): return ticket.subject
        case .accessRequest: return "Support-Datenzugriff"
        }
    }
    
    var message: String {
        switch self {
        case .ticket(let ticket): return ticket.message
        case .accessRequest(let request): return request.message
        }
    }
    
    var status: String {
        switch self {
        case .ticket(let ticket): return ticket.status
        case .accessRequest(let request): return request.status
        }
    }
}
