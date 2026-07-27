import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()
def env = System.getenv()

def user = env['JENKINS_ADMIN_ID']
def password = env['JENKINS_ADMIN_PASSWORD']

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount(user, password)
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
instance.setAuthorizationStrategy(strategy)
instance.save()
