public without sharing class UserProfileTriggerHandler {
    public static Boolean active = true;
    public static final String B2B_COMMERCE_PROFILE_NAME = 'Customer Community Plus Login IC';
    public static final String B2B_CUSTOMER_COMMUNITY_USER = 'Customer_Community_User';

    public static Boolean ALL_OR_NONE = true;

	public static void handleBeforeInsert(List<User> newUsers) {	
        if(active) {
            // validate usernames are not duplicates
            Set<String> usernames = new Set<String>();
            Map<String, User> usernameMap = new Map<String, User>();
            for(User userValidate : newUsers) {
                if(String.isNotBlank(userValidate.Email)) {
                    usernames.add(userValidate.Email);
                    usernameMap.put(userValidate.Email, userValidate);
                }
            }
            if(!usernames.isEmpty()) {
                List<User> users = [SELECT Id, Username FROM User WHERE Username IN :usernames];
                if(!users.isEmpty()) {
                    for(User userError : users) {
                        User user = usernameMap.get(userError.Username);
                        user.addError(Label.USERNAME_IS_DUPLICATE);
                    }
                } else {
                    Profile communityProfile = [SELECT Id FROM Profile WHERE Name = :B2B_COMMERCE_PROFILE_NAME LIMIT 1];

                    // contact needs account, use account of user creating new user
                    List<User> loggedInUser = [SELECT Name, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
                    Id accountId = null;
                    if(!loggedInUser.isEmpty()) {
                        accountId = loggedInUser[0].AccountId;
                    }
        
                    for(User userAdd : newUsers){
                        // create contact
                        Contact newContact = createB2BContactForUser(userAdd, accountId);
                        userAdd.ContactId = newContact.Id;
                        if(userAdd.ProfileId == null) {
                            userAdd.ProfileId = communityProfile.Id;
                        }
                        userAdd.Username = userAdd.Email;
                        userAdd.Alias = getAliasFromUser(userAdd);
                        userAdd.CommunityNickname = getCommunityNicknameFromUser(userAdd);
                    }
                }
            }

		}
	}

    public static void handleAfterInsert(List<User> newUsers) {
        if(active) {
            Set<Id> userIds = new Set<Id>();
			for(User user : newUsers) {
				userIds.add(user.Id);
			}
			if(!userIds.isEmpty()) {
				createPermissionSetGroupAssignmentsForUsers(userIds);
			}
        }
    }

    public static void handleBeforeUpdate(Map<Id, User> oldMap, Map<Id, User> newMap) {
		if (active) {
            //validate usernames are not duplicates
            Set<String> usernames = new Set<String>();
            Map<String, User> usernameMap = new Map<String, User>();
            String query = 'SELECT Id, Username FROM User WHERE ';
            List<String> queryParts = new List<String>();
            
            for(User userValidate : newMap.values()) {
                User oldUser = oldMap.get(userValidate.Id);
                if(String.isNotBlank(userValidate.Email) && oldUser.Email != userValidate.Email) {
                    usernames.add(userValidate.Email);
                    usernameMap.put(userValidate.Email, userValidate);
                    queryParts.add('(ContactId != \'' + userValidate.ContactId + '\' AND Username = \'' + String.escapeSingleQuotes(userValidate.Email)+'\') ');
                }
            }
            if (!queryParts.isEmpty()) {
                query += String.join(queryParts, ' OR ');
            }

            if(!usernames.isEmpty()) {
                List<User> users = Database.query(query);
                for(User userError : users) {
                    User user = usernameMap.get(userError.Username);
                    user.addError(Label.USERNAME_IS_DUPLICATE);
                }
            }
		}
	}

    public static void handleAfterUpdate(Map<Id, User> oldMap, Map<Id, User> newMap) {
		if(active) {
			Set<Id> updatedContacts = new Set<Id>();
			for(User user : newMap.values()) {
				updatedContacts.add(user.ContactId);
			}
            
            updateExistingContacts(updatedContacts);

		}
	}

    private static Contact createB2BContactForUser(User u, Id accountId) {
		Contact c = new Contact();
        c.FirstName = u.FirstName;
        c.LastName = u.LastName;
        c.Email = u.Email;
        c.AccountId = accountId; 
		Database.insert(c);
		return c;
	}

    private static String getCommunityNicknameFromUser(User u) {
		String str = getRandomString(); //add random string to prevent duplicates
		String nick = u.FirstName != null ? u.FirstName + u.LastName + str : u.LastName + str;
		if(nick.length() > 40) {
			return nick.substring(0,40);
		}
		return nick;
	}

	private static String getAliasFromUser(User u) {
		String str = getRandomString();
		String alias = u.FirstName != null ? u.FirstName + u.LastName + str : u.LastName + str;
		alias = alias.replace(' ', '');
		if(alias.length() > 8) {
			return alias.substring(0,8);
		}
		return alias;
	}

	private static String getRandomString() {
		Blob blobkey = crypto.generateAesKey(128);
		String key = EncodingUtil.convertToHex(blobkey);
		return key.substring(0,10);
	}

	@future
    private static void createPermissionSetGroupAssignmentsForUsers(Set<Id> userIds) {
		List<PermissionSetGroup> permissionSetGroups = [
			SELECT Id 
			FROM PermissionSetGroup 
			WHERE DeveloperName = :B2B_CUSTOMER_COMMUNITY_USER
		];

		List<PermissionSetAssignment> permissionSetGroupAssignmentsToCreate = new List<PermissionSetAssignment>();
		for(Id userId : userIds) {
			// assign to each user
			for (PermissionSetGroup psg : permissionSetGroups) {
				PermissionSetAssignment psga = new PermissionSetAssignment();
				psga.AssigneeId = userId;
				psga.PermissionSetGroupId = psg.Id;
				permissionSetGroupAssignmentsToCreate.add(psga);
			}
		}
		Database.insert(permissionSetGroupAssignmentsToCreate, ALL_OR_NONE);
	}

    @future
    private static void updateExistingContacts(Set<Id> updatedContacts) {
        // find contact and update fields
        List<Contact> existingContacts = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Id IN :updatedContacts];
        List<User> updatedUsers = [SELECT Id, FirstName, LastName, Email, ContactId FROM User WHERE ContactId IN :updatedContacts];

        Map<Id, User> contactMappedUsers = new Map<Id, User>();
        for(User u : updatedUsers) {
            contactMappedUsers.put(u.ContactId, u);
        }

        for(Contact c : existingContacts) {
            User contactUser = contactMappedUsers.get(c.Id);
            c.FirstName = contactUser.FirstName;
            c.LastName = contactUser.LastName;
            c.Email = contactUser.Email;
        }

        update existingContacts;

	}
}