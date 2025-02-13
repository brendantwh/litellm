import { teamListCall, DEFAULT_ORGANIZATION, Organization } from "../networking";

export const fetchTeams = async (accessToken: string, userID: string | null, userRole: string | null, currentOrg: Organization | null, setTeams: (teams: any[]) => void) => {
    let givenTeams;
    if (userRole != "Admin" && userRole != "Admin Viewer") {
      givenTeams = await teamListCall(accessToken, currentOrg?.organization_id || DEFAULT_ORGANIZATION, userID)
    } else {
      givenTeams = await teamListCall(accessToken, currentOrg?.organization_id || DEFAULT_ORGANIZATION)
    }
    
    console.log(`givenTeams: ${givenTeams}`)

    setTeams(givenTeams)
  }