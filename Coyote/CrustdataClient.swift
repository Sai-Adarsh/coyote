import Foundation

private func crustLog(_ msg: String) {
    let line = "\(Date()) [Crustdata] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Coyote-Crustdata.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: url)
    }
}

actor CrustdataClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.crustdata.com"
    private let apiVersion = "2025-11-01"
    private var cache: [String: CachedResult] = [:]
    private var activeRequests: Int = 0
    private let maxConcurrent: Int = 4

    struct CachedResult {
        let personResult: CrustdataPersonResult?
        let companyResult: CrustdataCompanyResult?
        let timestamp: Date
    }

    init(apiToken: String) {
        self.apiKey = apiToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Company API

    func searchCompany(name: String) async -> [CrustdataCompanyResult] {
        await throttle()

        // POST /company/search — filter by basic_info.name
        // Returns full data: basic_info, headcount, funding, revenue, locations, taxonomy
        let body: [String: Any] = [
            "filters": [
                "field": "basic_info.name",
                "type": "=",
                "value": name
            ],
            "limit": 3
        ]

        guard let response: CompanySearchResponse = await postRequest(endpoint: "/company/search", body: body) else {
            return []
        }

        return response.companies?.prefix(3).compactMap { mapCompanySearchResult($0) } ?? []
    }

    func enrichCompany(name: String) async -> CrustdataCompanyResult? {
        let key = "company:\(name.lowercased())"
        if let cached = cache[key] {
            crustLog("Cache hit for \(key)")
            return cached.companyResult
        }

        // Strategy: Use /company/search as primary — it returns full data (headcount, funding, revenue, locations).
        // /company/enrich only returns basic_info. So search first, fall back to enrich for name matching only.
        await throttle()

        let searchBody: [String: Any] = [
            "filters": [
                "field": "basic_info.name",
                "type": "=",
                "value": name
            ],
            "limit": 1
        ]

        if let searchResponse: CompanySearchResponse = await postRequest(endpoint: "/company/search", body: searchBody),
           let firstCompany = searchResponse.companies?.first,
           let result = mapCompanySearchResult(firstCompany) {
            cache[key] = CachedResult(personResult: nil, companyResult: result, timestamp: Date())
            return result
        }

        // Fallback: /company/enrich (returns array, only basic_info in company_data)
        await throttle()
        let enrichBody: [String: Any] = ["names": [name]]

        guard let enrichResults: [CompanyEnrichResult] = await postRequest(endpoint: "/company/enrich", body: enrichBody) else {
            return nil
        }

        guard let firstResult = enrichResults.first,
              let bestMatch = firstResult.matches?.max(by: { ($0.confidenceScore ?? 0) < ($1.confidenceScore ?? 0) }),
              let companyData = bestMatch.companyData,
              let basicInfo = companyData.basicInfo,
              let resultName = basicInfo.name else { return nil }

        let result = CrustdataCompanyResult(
            name: resultName,
            website: basicInfo.website,
            domain: basicInfo.primaryDomain,
            industry: basicInfo.industries?.first,
            employeeCount: nil,
            employeeRange: basicInfo.employeeCountRange,
            revenueRangePrinted: nil,
            founded: parseYear(basicInfo.yearFounded),
            totalFunding: nil,
            latestFundingStage: nil,
            latestFundingDate: nil,
            descriptionAi: basicInfo.description_field,
            location: nil,
            logoUrl: basicInfo.logoPermalink,
            linkedinUrl: basicInfo.professionalNetworkUrl,
            keywords: basicInfo.industries ?? [],
            type: basicInfo.companyType
        )
        cache[key] = CachedResult(personResult: nil, companyResult: result, timestamp: Date())
        return result
    }

    // MARK: - Person API

    func searchPerson(name: String, companyName: String? = nil) async -> [CrustdataPersonResult] {
        await throttle()

        // POST /person/search — filter by basic_profile.name + optionally employer
        var body: [String: Any]

        if let companyName, !companyName.isEmpty {
            body = [
                "filters": [
                    "op": "and",
                    "conditions": [
                        ["field": "basic_profile.name", "type": "=", "value": name],
                        ["field": "experience.employment_details.company_name", "type": "in", "value": [companyName]]
                    ]
                ] as [String: Any],
                "limit": 3
            ]
        } else {
            body = [
                "filters": [
                    "field": "basic_profile.name",
                    "type": "=",
                    "value": name
                ] as [String: Any],
                "limit": 3
            ]
        }

        guard let response: PersonSearchResponse = await postRequest(endpoint: "/person/search", body: body) else {
            return []
        }

        return response.profiles?.prefix(3).compactMap { mapPersonResult($0) } ?? []
    }

    func enrichPerson(firstName: String, lastName: String, companyName: String?) async -> CrustdataPersonResult? {
        let fullName = "\(firstName) \(lastName)"
        let key = "person:\(fullName.lowercased())"
        if let cached = cache[key] {
            crustLog("Cache hit for \(key)")
            return cached.personResult
        }

        await throttle()

        // Person enrich requires linkedin URL or email — since we only have a name,
        // fall back to person search with limit 1 as a best-effort enrichment.
        var body: [String: Any]

        if let companyName, !companyName.isEmpty {
            body = [
                "filters": [
                    "op": "and",
                    "conditions": [
                        ["field": "basic_profile.name", "type": "=", "value": fullName],
                        ["field": "experience.employment_details.company_name", "type": "in", "value": [companyName]]
                    ]
                ] as [String: Any],
                "limit": 1
            ]
        } else {
            body = [
                "filters": [
                    "field": "basic_profile.name",
                    "type": "=",
                    "value": fullName
                ] as [String: Any],
                "limit": 1
            ]
        }

        guard let response: PersonSearchResponse = await postRequest(endpoint: "/person/search", body: body) else {
            return nil
        }

        guard let profiles = response.profiles, let first = profiles.first else { return nil }

        let result = mapPersonResult(first)
        cache[key] = CachedResult(personResult: result, companyResult: nil, timestamp: Date())
        return result
    }

    // MARK: - Web API (Live News)

    func webSearch(query: String) async -> [CrustdataWebResult] {
        await throttle()

        // POST /web/search/live — live web search (no limit param — returns all results)
        let body: [String: Any] = [
            "query": query
        ]

        guard let response: WebSearchResponse = await postRequest(endpoint: "/web/search/live", body: body) else {
            return []
        }

        return response.results ?? []
    }

    // MARK: - Full Enrich (Person)

    func fullEnrichPerson(linkedinUrl: String) async -> CrustdataPersonResult? {
        await throttle()

        // POST /person/enrich — requires professional_network_profile_urls (array)
        let body: [String: Any] = [
            "professional_network_profile_urls": [linkedinUrl]
        ]

        crustLog("Full enrich person: \(linkedinUrl)")

        guard let results: [PersonFullEnrichResult] = await postRequest(endpoint: "/person/enrich", body: body) else {
            return nil
        }

        guard let first = results.first,
              let bestMatch = first.matches?.max(by: { ($0.confidenceScore ?? 0) < ($1.confidenceScore ?? 0) }),
              let personData = bestMatch.personData else { return nil }

        return mapFullEnrichPerson(personData)
    }

    // MARK: - Full Enrich (Company)

    func fullEnrichCompany(domain: String?, name: String) async -> CrustdataCompanyResult? {
        await throttle()

        // /company/enrich with domain or name
        var body: [String: Any] = [:]
        if let domain, !domain.isEmpty {
            body["domains"] = [domain]
        } else {
            body["names"] = [name]
        }

        crustLog("Full enrich company: domain=\(domain ?? "nil") name=\(name)")

        guard let enrichResults: [CompanyEnrichResult] = await postRequest(endpoint: "/company/enrich", body: body) else {
            return nil
        }

        guard let firstResult = enrichResults.first,
              let bestMatch = firstResult.matches?.max(by: { ($0.confidenceScore ?? 0) < ($1.confidenceScore ?? 0) }),
              let companyData = bestMatch.companyData,
              let basicInfo = companyData.basicInfo,
              let resultName = basicInfo.name else { return nil }

        return CrustdataCompanyResult(
            name: resultName,
            website: basicInfo.website,
            domain: basicInfo.primaryDomain,
            industry: basicInfo.industries?.first,
            employeeCount: nil,
            employeeRange: basicInfo.employeeCountRange,
            revenueRangePrinted: nil,
            founded: parseYear(basicInfo.yearFounded),
            totalFunding: nil,
            latestFundingStage: nil,
            latestFundingDate: nil,
            descriptionAi: basicInfo.description_field,
            location: nil,
            logoUrl: basicInfo.logoPermalink,
            linkedinUrl: basicInfo.professionalNetworkUrl,
            keywords: basicInfo.industries ?? [],
            type: basicInfo.companyType,
            specialities: companyData.taxonomy?.professionalNetworkSpecialities ?? []
        )
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Networking

    private func throttle() async {
        while activeRequests >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        activeRequests += 1
    }

    private func unthrottle() {
        activeRequests = max(0, activeRequests - 1)
    }

    private func postRequest<T: Decodable>(endpoint: String, body: [String: Any], retryCount: Int = 0) async -> T? {
        guard let url = URL(string: baseURL + endpoint) else {
            crustLog("ERROR: Invalid URL: \(self.baseURL)\(endpoint)")
            unthrottle()
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "x-api-version")

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData
            let bodyStr = String(data: bodyData, encoding: .utf8) ?? "?"
            crustLog("POST \(endpoint) body=\(bodyStr.prefix(300))")

            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? -1
            let responseStr = String(data: data, encoding: .utf8) ?? "?"
            crustLog("\(endpoint) status=\(statusCode) response=\(responseStr.prefix(500))")

            if statusCode == 429 && retryCount < 2 {
                let waitTime = Double(retryCount + 1) * 5.0
                crustLog("Rate limited, retrying in \(waitTime)s (attempt \(retryCount + 1))")
                unthrottle()
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                return await postRequest(endpoint: endpoint, body: body, retryCount: retryCount + 1)
            }

            unthrottle()

            guard (200...299).contains(statusCode) else {
                crustLog("ERROR: \(endpoint) HTTP \(statusCode)")
                return nil
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            unthrottle()
            crustLog("ERROR: \(endpoint) \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Mapping: Person

    private func mapPersonResult(_ profile: PersonProfile) -> CrustdataPersonResult? {
        let name = profile.basicProfile?.name ?? ""
        guard !name.isEmpty else { return nil }

        // Location: use raw field (e.g. "San Francisco Bay Area"), fall back to city/state/country
        let location: String? = profile.basicProfile?.location?.raw ?? {
            let parts = [profile.basicProfile?.location?.city, profile.basicProfile?.location?.state, profile.basicProfile?.location?.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }()

        // Extract current employer info from experience
        // API returns: name, title, professional_network_id, crustdata_company_id, start_date, etc.
        var companyResult: CrustdataCompanyResult? = nil
        if let current = profile.experience?.employmentDetails?.current, let first = current.first {
            companyResult = CrustdataCompanyResult(
                name: first.name ?? "Unknown",
                website: nil,
                domain: nil,
                industry: nil,
                employeeCount: nil,
                employeeRange: nil,
                revenueRangePrinted: nil,
                founded: nil,
                totalFunding: nil,
                latestFundingStage: nil,
                latestFundingDate: nil,
                descriptionAi: nil,
                location: nil,
                logoUrl: nil,
                linkedinUrl: first.companyProfessionalNetworkProfileUrl,
                keywords: [],
                type: nil
            )
        }

        let profileUrl = profile.socialHandles?.professionalNetworkIdentifier?.profileUrl

        return CrustdataPersonResult(
            fullName: name,
            title: profile.basicProfile?.currentTitle ?? profile.basicProfile?.headline,
            email: nil, // Email not directly returned in search results
            linkedinUrl: profileUrl,
            location: location?.isEmpty == true ? nil : location,
            company: companyResult
        )
    }

    // MARK: - Mapping: Person Full Enrich

    private func mapFullEnrichPerson(_ data: PersonFullEnrichData) -> CrustdataPersonResult? {
        let name = data.basicProfile?.name ?? data.professionalNetwork?.name ?? ""
        guard !name.isEmpty else { return nil }

        let location = data.basicProfile?.location?.raw ?? {
            let parts = [data.basicProfile?.location?.city, data.basicProfile?.location?.state, data.basicProfile?.location?.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }()

        // Current employer
        var companyResult: CrustdataCompanyResult? = nil
        if let current = data.experience?.employmentDetails?.current {
            let defaultEmployer = current.first(where: { $0.isDefault == true }) ?? current.first
            if let emp = defaultEmployer {
                companyResult = CrustdataCompanyResult(
                    name: emp.name ?? "Unknown",
                    website: nil, domain: emp.companyWebsiteDomain,
                    industry: nil, employeeCount: nil, employeeRange: nil,
                    revenueRangePrinted: nil, founded: nil, totalFunding: nil,
                    latestFundingStage: nil, latestFundingDate: nil,
                    descriptionAi: emp.description_field,
                    location: emp.location?.raw,
                    logoUrl: emp.companyProfilePicturePermalink,
                    linkedinUrl: emp.companyProfessionalNetworkProfileUrl,
                    keywords: [], type: nil
                )
            }
        }

        // Education
        let education = (data.education?.schools ?? []).compactMap { school -> PersonEducationEntry? in
            guard let name = school.school, !name.isEmpty else { return nil }
            return PersonEducationEntry(school: name, degree: school.degree, fieldOfStudy: school.fieldOfStudy, startYear: school.startYear, endYear: school.endYear)
        }

        // Past employment
        let pastEmployment = (data.experience?.employmentDetails?.past ?? []).compactMap { emp -> PersonEmploymentEntry? in
            guard let name = emp.name, !name.isEmpty else { return nil }
            return PersonEmploymentEntry(company: name, title: emp.title, startDate: emp.startDate, endDate: emp.endDate)
        }

        // Business emails
        let emails = (data.contact?.businessEmails ?? []).compactMap { $0.email }

        // Skills
        let skills = data.skills?.professionalNetworkSkills ?? []

        // Social handles
        let linkedinUrl = data.socialHandles?.professionalNetworkIdentifier?.profileUrl
        let twitterHandle = data.socialHandles?.twitterIdentifier?.slug
        let githubUrl = data.devPlatformProfiles?.first?.profileUrl

        let title = data.basicProfile?.currentTitle ?? data.professionalNetwork?.currentTitle
        let headline = data.basicProfile?.headline ?? data.professionalNetwork?.headline
        let followers = data.professionalNetwork?.followers

        return CrustdataPersonResult(
            fullName: name,
            title: title,
            email: emails.first,
            linkedinUrl: linkedinUrl,
            location: location?.isEmpty == true ? nil : location,
            company: companyResult,
            summary: data.basicProfile?.summary ?? data.professionalNetwork?.summary,
            headline: headline,
            profilePictureUrl: data.basicProfile?.profilePicturePermalink ?? data.professionalNetwork?.profilePicturePermalink,
            twitterHandle: twitterHandle,
            githubUrl: githubUrl,
            businessEmails: emails,
            education: education,
            skills: skills,
            pastEmployment: pastEmployment,
            languages: data.basicProfile?.languages ?? [],
            linkedinFollowers: followers
        )
    }

    // MARK: - Mapping: Company Search

    private func mapCompanySearchResult(_ company: CompanySearchRecord) -> CrustdataCompanyResult? {
        guard let basicInfo = company.basicInfo, let name = basicInfo.name else { return nil }

        let fundingTotal: String? = company.funding?.totalInvestmentUsd.map { "$\(formatLargeNumber($0))" }

        // Locations come as country/state/city (not hq-prefixed)
        let locationParts = [company.locations?.city, company.locations?.state, company.locations?.country]
            .compactMap { $0 }
        let location = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")

        return CrustdataCompanyResult(
            name: name,
            website: basicInfo.website,
            domain: basicInfo.primaryDomain,
            industry: basicInfo.industries?.first,
            employeeCount: company.headcount?.total,
            employeeRange: basicInfo.employeeCountRange,
            revenueRangePrinted: formatRevenueRange(company.revenue?.estimated),
            founded: parseYear(basicInfo.yearFounded),
            totalFunding: fundingTotal,
            latestFundingStage: company.funding?.lastRoundType,
            latestFundingDate: company.funding?.lastFundraiseDate,
            descriptionAi: basicInfo.description_field,
            location: location,
            logoUrl: basicInfo.logoPermalink,
            linkedinUrl: basicInfo.professionalNetworkUrl,
            keywords: basicInfo.industries ?? [],
            type: basicInfo.companyType
        )
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Double) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", n / 1_000) }
        return String(format: "%.0f", n)
    }

    private func formatRevenueRange(_ estimated: RevenueEstimated?) -> String? {
        guard let est = estimated else { return nil }
        if let lower = est.lowerBoundUsd, let upper = est.upperBoundUsd {
            return "$\(formatLargeNumber(lower)) – $\(formatLargeNumber(upper))"
        }
        return nil
    }

    private func parseYear(_ dateStr: String?) -> Int? {
        guard let ds = dateStr else { return nil }
        if ds.count >= 4, let y = Int(ds.prefix(4)) { return y }
        return nil
    }
}

// MARK: - Public Result Models

struct CrustdataPersonResult: Identifiable, Sendable {
    let id = UUID()
    let fullName: String
    let title: String?
    let email: String?
    let linkedinUrl: String?
    let location: String?
    let company: CrustdataCompanyResult?
    // Full-enrich fields
    let summary: String?
    let headline: String?
    let profilePictureUrl: String?
    let twitterHandle: String?
    let githubUrl: String?
    let businessEmails: [String]
    let education: [PersonEducationEntry]
    let skills: [String]
    let pastEmployment: [PersonEmploymentEntry]
    let languages: [String]
    let linkedinFollowers: Int?

    init(fullName: String, title: String?, email: String?, linkedinUrl: String?, location: String?, company: CrustdataCompanyResult?,
         summary: String? = nil, headline: String? = nil, profilePictureUrl: String? = nil,
         twitterHandle: String? = nil, githubUrl: String? = nil, businessEmails: [String] = [],
         education: [PersonEducationEntry] = [], skills: [String] = [], pastEmployment: [PersonEmploymentEntry] = [],
         languages: [String] = [], linkedinFollowers: Int? = nil) {
        self.fullName = fullName; self.title = title; self.email = email
        self.linkedinUrl = linkedinUrl; self.location = location; self.company = company
        self.summary = summary; self.headline = headline; self.profilePictureUrl = profilePictureUrl
        self.twitterHandle = twitterHandle; self.githubUrl = githubUrl; self.businessEmails = businessEmails
        self.education = education; self.skills = skills; self.pastEmployment = pastEmployment
        self.languages = languages; self.linkedinFollowers = linkedinFollowers
    }
}

struct PersonEducationEntry: Identifiable, Sendable {
    let id = UUID()
    let school: String
    let degree: String?
    let fieldOfStudy: String?
    let startYear: Int?
    let endYear: Int?
}

struct PersonEmploymentEntry: Identifiable, Sendable {
    let id = UUID()
    let company: String
    let title: String?
    let startDate: String?
    let endDate: String?
}

struct CrustdataCompanyResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let website: String?
    let domain: String?
    let industry: String?
    let employeeCount: Int?
    let employeeRange: String?
    let revenueRangePrinted: String?
    let founded: Int?
    let totalFunding: String?
    let latestFundingStage: String?
    let latestFundingDate: String?
    let descriptionAi: String?
    let location: String?
    let logoUrl: String?
    let linkedinUrl: String?
    let keywords: [String]
    let type: String?
    // Full-enrich fields
    let allDomains: [String]
    let specialities: [String]
    let investors: [String]

    init(name: String, website: String?, domain: String?, industry: String?, employeeCount: Int?, employeeRange: String?,
         revenueRangePrinted: String?, founded: Int?, totalFunding: String?, latestFundingStage: String?, latestFundingDate: String?,
         descriptionAi: String?, location: String?, logoUrl: String?, linkedinUrl: String?, keywords: [String], type: String?,
         allDomains: [String] = [], specialities: [String] = [], investors: [String] = []) {
        self.name = name; self.website = website; self.domain = domain; self.industry = industry
        self.employeeCount = employeeCount; self.employeeRange = employeeRange; self.revenueRangePrinted = revenueRangePrinted
        self.founded = founded; self.totalFunding = totalFunding; self.latestFundingStage = latestFundingStage
        self.latestFundingDate = latestFundingDate; self.descriptionAi = descriptionAi; self.location = location
        self.logoUrl = logoUrl; self.linkedinUrl = linkedinUrl; self.keywords = keywords; self.type = type
        self.allDomains = allDomains; self.specialities = specialities; self.investors = investors
    }
}

struct CrustdataWebResult: Identifiable, Sendable, Decodable {
    var id: String { url ?? UUID().uuidString }
    let source: String?
    let title: String?
    let url: String?
    let snippet: String?
    let position: Int?

    private enum CodingKeys: String, CodingKey {
        case source, title, url, snippet, position
    }
}

// MARK: - Person API Response Models

// Actual response: {"profiles": [...], "next_cursor": "...", "total_count": 344}
private struct PersonSearchResponse: Decodable {
    let profiles: [PersonProfile]?
    let totalCount: Int?
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case profiles, totalCount, nextCursor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.profiles = try? container.decode([PersonProfile].self, forKey: .profiles)
        self.totalCount = try? container.decode(Int.self, forKey: .totalCount)
        self.nextCursor = try? container.decode(String.self, forKey: .nextCursor)
    }
}

// Actual keys: crustdata_person_id, basic_profile, social_handles, contact, education, experience
private struct PersonProfile: Decodable {
    let crustdataPersonId: Int?
    let basicProfile: PersonBasicProfile?
    let experience: PersonExperience?
    let education: PersonEducation?
    let contact: PersonContact?
    let socialHandles: PersonSocialHandles?

    private enum CodingKeys: String, CodingKey {
        case crustdataPersonId, basicProfile, experience, education, contact, socialHandles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.crustdataPersonId = try? container.decode(Int.self, forKey: .crustdataPersonId)
        self.basicProfile = try? container.decode(PersonBasicProfile.self, forKey: .basicProfile)
        self.experience = try? container.decode(PersonExperience.self, forKey: .experience)
        self.education = try? container.decode(PersonEducation.self, forKey: .education)
        self.contact = try? container.decode(PersonContact.self, forKey: .contact)
        self.socialHandles = try? container.decode(PersonSocialHandles.self, forKey: .socialHandles)
    }
}

// Actual: name, headline, current_title, location {raw, city, state, country, continent}, profile_picture_permalink
private struct PersonBasicProfile: Decodable {
    let name: String?
    let headline: String?
    let currentTitle: String?
    let location: PersonLocation?
    let profilePicturePermalink: String?
    let summary: String?
    let languages: [String]?
}

// Actual: raw, city, state, country, continent
private struct PersonLocation: Decodable {
    let raw: String?
    let city: String?
    let state: String?
    let country: String?
    let continent: String?
}

private struct PersonExperience: Decodable {
    let employmentDetails: EmploymentDetails?
}

private struct EmploymentDetails: Decodable {
    let current: [EmploymentRecord]?
    let past: [EmploymentRecord]?
}

// Actual: name, professional_network_id, title, location, start_date, end_date,
//         is_default, crustdata_company_id, company_profile_picture_permalink,
//         company_professional_network_profile_url
private struct EmploymentRecord: Decodable {
    let name: String?
    let title: String?
    let professionalNetworkId: String?
    let location: String?
    let startDate: String?
    let endDate: String?
    let isDefault: Bool?
    let crustdataCompanyId: Int?
    let companyProfilePicturePermalink: String?
    let companyProfessionalNetworkProfileUrl: String?

    private enum CodingKeys: String, CodingKey {
        case name, title, professionalNetworkId, location, startDate, endDate
        case isDefault, crustdataCompanyId, companyProfilePicturePermalink
        case companyProfessionalNetworkProfileUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try? container.decode(String.self, forKey: .name)
        self.title = try? container.decode(String.self, forKey: .title)
        self.professionalNetworkId = try? container.decode(String.self, forKey: .professionalNetworkId)
        self.location = try? container.decode(String.self, forKey: .location)
        self.startDate = try? container.decode(String.self, forKey: .startDate)
        self.endDate = try? container.decode(String.self, forKey: .endDate)
        self.isDefault = try? container.decode(Bool.self, forKey: .isDefault)
        self.crustdataCompanyId = try? container.decode(Int.self, forKey: .crustdataCompanyId)
        self.companyProfilePicturePermalink = try? container.decode(String.self, forKey: .companyProfilePicturePermalink)
        self.companyProfessionalNetworkProfileUrl = try? container.decode(String.self, forKey: .companyProfessionalNetworkProfileUrl)
    }
}

private struct PersonEducation: Decodable {
    let schools: [SchoolRecord]?
}

// Actual: school, degree, field_of_study, start_year, end_year, professional_network_id
private struct SchoolRecord: Decodable {
    let school: String?
    let degree: String?
    let fieldOfStudy: String?
    let startYear: Int?
    let endYear: Int?

    private enum CodingKeys: String, CodingKey {
        case school, degree, fieldOfStudy, startYear, endYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.school = try? container.decode(String.self, forKey: .school)
        self.degree = try? container.decode(String.self, forKey: .degree)
        self.fieldOfStudy = try? container.decode(String.self, forKey: .fieldOfStudy)
        self.startYear = try? container.decode(Int.self, forKey: .startYear)
        self.endYear = try? container.decode(Int.self, forKey: .endYear)
    }
}

// Actual: has_business_email, has_personal_email, has_phone_number
private struct PersonContact: Decodable {
    let hasBusinessEmail: Bool?
    let hasPersonalEmail: Bool?
    let hasPhoneNumber: Bool?
    let businessEmails: [BusinessEmail]?
}

private struct BusinessEmail: Decodable {
    let email: String?
    let status: String?
}

// Actual: professional_network_identifier { profile_url }, twitter_identifier, dev_platform_identifier
private struct PersonSocialHandles: Decodable {
    let professionalNetworkIdentifier: ProfessionalNetworkId?
    let twitterIdentifier: TwitterId?
}

private struct ProfessionalNetworkId: Decodable {
    let profileUrl: String?
}

private struct TwitterId: Decodable {
    let slug: String?
}

// MARK: - Company Search Response Models

// Actual: {"companies": [...], "next_cursor": "...", "total_count": N}
// Each company has: crustdata_company_id, metadata, basic_info, revenue, headcount,
//   software_reviews, funding, hiring, locations, social_profiles, taxonomy, followers
private struct CompanySearchResponse: Decodable {
    let companies: [CompanySearchRecord]?
    let nextCursor: String?
    let totalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case companies, nextCursor, totalCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.companies = try? container.decode([CompanySearchRecord].self, forKey: .companies)
        self.nextCursor = try? container.decode(String.self, forKey: .nextCursor)
        self.totalCount = try? container.decode(Int.self, forKey: .totalCount)
    }
}

private struct CompanySearchRecord: Decodable {
    let crustdataCompanyId: Int?
    let basicInfo: CompanyBasicInfo?
    let headcount: CompanyHeadcount?
    let funding: CompanyFunding?
    let locations: CompanyLocations?
    let taxonomy: CompanyTaxonomy?
    let revenue: CompanyRevenue?
}

// MARK: - Company Enrich Response Models

// Actual response is a JSON array: [{matched_on, match_type, matches: [{confidence_score, company_data}]}]
// company_data only contains: crustdata_company_id, basic_info
private struct CompanyEnrichResult: Decodable {
    let matchedOn: String?
    let matchType: String?
    let matches: [CompanyEnrichMatch]?
}

private struct CompanyEnrichMatch: Decodable {
    let confidenceScore: Double?
    let companyData: CompanyEnrichData?
}

private struct CompanyEnrichData: Decodable {
    let crustdataCompanyId: Int?
    let basicInfo: CompanyBasicInfo?
    let taxonomy: CompanyTaxonomy?
}

// MARK: - Shared Company Sub-Models

// Actual basic_info: name, primary_domain, all_domains, website, logo_permalink, description,
//   company_type, year_founded, employee_count_range, markets, industries,
//   crustdata_company_id, professional_network_id, professional_network_url, profile_name
private struct CompanyBasicInfo: Decodable {
    let name: String?
    let primaryDomain: String?
    let website: String?
    let professionalNetworkUrl: String?
    let yearFounded: String?
    let description_field: String?
    let companyType: String?
    let employeeCountRange: String?
    let industries: [String]?
    let logoPermalink: String?
    let profileName: String?

    private enum CodingKeys: String, CodingKey {
        case name, primaryDomain, website, professionalNetworkUrl, yearFounded
        case description_field = "description"
        case companyType, employeeCountRange, industries, logoPermalink, profileName
    }
}

// Actual: {total, largest_headcount_country}
private struct CompanyHeadcount: Decodable {
    let total: Int?
}

// Actual: {total_investment_usd, last_round_amount_usd, last_fundraise_date, last_round_type, investors}
private struct CompanyFunding: Decodable {
    let totalInvestmentUsd: Double?
    let lastRoundAmountUsd: Double?
    let lastFundraiseDate: String?
    let lastRoundType: String?
    let investors: [String]?
}

// Actual: {country, state, city} (NOT hq-prefixed)
private struct CompanyLocations: Decodable {
    let country: String?
    let state: String?
    let city: String?
}

private struct CompanyTaxonomy: Decodable {
    let categories: [String]?
    let professionalNetworkIndustry: String?
    let professionalNetworkSpecialities: [String]?
}

// Actual: {estimated: {lower_bound_usd, upper_bound_usd}, public_markets: {...}, acquisition_status}
private struct CompanyRevenue: Decodable {
    let estimated: RevenueEstimated?
}

private struct RevenueEstimated: Decodable {
    let lowerBoundUsd: Double?
    let upperBoundUsd: Double?
}

// MARK: - Person Full Enrich Response Models

// Response: [{matched_on, match_type, matches: [{confidence_score, person_data}]}]
private struct PersonFullEnrichResult: Decodable {
    let matchedOn: String?
    let matchType: String?
    let matches: [PersonFullEnrichMatch]?
}

private struct PersonFullEnrichMatch: Decodable {
    let confidenceScore: Double?
    let personData: PersonFullEnrichData?
}

private struct PersonFullEnrichData: Decodable {
    let basicProfile: PersonBasicProfile?
    let experience: PersonFullExperience?
    let education: PersonEducation?
    let contact: PersonContact?
    let socialHandles: PersonSocialHandles?
    let skills: PersonSkills?
    let professionalNetwork: ProfessionalNetworkProfile?
    let devPlatformProfiles: [DevPlatformProfile]?
    let crustdataPersonId: Int?
}

private struct PersonFullExperience: Decodable {
    let employmentDetails: FullEmploymentDetails?
}

private struct FullEmploymentDetails: Decodable {
    let current: [FullEnrichEmploymentRecord]?
    let past: [FullEnrichEmploymentRecord]?
}

private struct FullEnrichEmploymentRecord: Decodable {
    let name: String?
    let title: String?
    let startDate: String?
    let endDate: String?
    let isDefault: Bool?
    let crustdataCompanyId: Int?
    let companyProfilePicturePermalink: String?
    let companyProfessionalNetworkProfileUrl: String?
    let companyWebsiteDomain: String?
    let description_field: String?
    let location: FullEnrichLocation?

    private enum CodingKeys: String, CodingKey {
        case name, title, startDate, endDate, isDefault, crustdataCompanyId
        case companyProfilePicturePermalink, companyProfessionalNetworkProfileUrl
        case companyWebsiteDomain
        case description_field = "description"
        case location
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try? container.decode(String.self, forKey: .name)
        self.title = try? container.decode(String.self, forKey: .title)
        self.startDate = try? container.decode(String.self, forKey: .startDate)
        self.endDate = try? container.decode(String.self, forKey: .endDate)
        self.isDefault = try? container.decode(Bool.self, forKey: .isDefault)
        self.crustdataCompanyId = try? container.decode(Int.self, forKey: .crustdataCompanyId)
        self.companyProfilePicturePermalink = try? container.decode(String.self, forKey: .companyProfilePicturePermalink)
        self.companyProfessionalNetworkProfileUrl = try? container.decode(String.self, forKey: .companyProfessionalNetworkProfileUrl)
        self.companyWebsiteDomain = try? container.decode(String.self, forKey: .companyWebsiteDomain)
        self.description_field = try? container.decode(String.self, forKey: .description_field)
        self.location = try? container.decode(FullEnrichLocation.self, forKey: .location)
    }
}

private struct FullEnrichLocation: Decodable {
    let raw: String?
}

private struct PersonSkills: Decodable {
    let professionalNetworkSkills: [String]?
}

private struct ProfessionalNetworkProfile: Decodable {
    let name: String?
    let headline: String?
    let currentTitle: String?
    let summary: String?
    let followers: Int?
    let connections: Int?
    let profilePicturePermalink: String?
}

private struct DevPlatformProfile: Decodable {
    let profileUrl: String?
    let name: String?
}

// MARK: - Web Search Response Models

// Actual: {success, query, timestamp, results: [{source, title, url, snippet, position}], metadata}
private struct WebSearchResponse: Decodable {
    let success: Bool?
    let results: [CrustdataWebResult]?

    private enum CodingKeys: String, CodingKey {
        case success, results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try? container.decode(Bool.self, forKey: .success)
        self.results = try? container.decode([CrustdataWebResult].self, forKey: .results)
    }
}
